import Foundation

/// T1 packaged-goods records from Open Food Facts (spec §5.4):
/// `GET https://world.openfoodfacts.org/api/v2/product/{gtin}.json?fields=…`, and for food without a barcode a text
/// search by brand and name: `GET https://search.openfoodfacts.org/search?q=…&page_size=20&fields=…`.
///
/// The search uses Open Food Facts' search service (search-a-licious) rather than the main site's `cgi/search.pl`:
/// it answers in about half a second with the same product fields (brands as a list), while `cgi/search.pl` is slow
/// and was returning 503s when this was written. Its records have Agribalyse carbon but usually no packaging.
public struct OpenFoodFactsClient: ProductDatabase {
    public static let userAgent = "LiveGreen/1.0 (HackHarvard)"
    static let fields = ["code", "product_name", "product_name_en", "brands", "product_quantity",
                         "product_quantity_unit", "quantity", "serving_quantity", "serving_quantity_unit", "categories_tags", "ecoscore_data", "packagings",
                         "image_front_url", "image_url"]
    /// Results a search reads: enough for several records of one product to agree on its figure.
    static let searchPageSize = 20

    public var baseURL: URL
    public var searchURL: URL
    public var timeout: Double
    /// A name search only improves on identify's estimate, so it gets one short try and never holds up a scan.
    public var searchTimeout: Double
    public var retry: RetryPolicy
    let transport: any HTTPTransport

    public init(baseURL: URL = URL(string: "https://world.openfoodfacts.org")!, timeout: Double = 10,
                retry: RetryPolicy = .default,
                searchURL: URL = URL(string: "https://search.openfoodfacts.org")!, searchTimeout: Double = 5,
                transport: any HTTPTransport = URLSessionTransport()) {
        self.baseURL = baseURL
        self.searchURL = searchURL
        self.timeout = timeout
        self.searchTimeout = searchTimeout
        self.retry = retry
        self.transport = transport
    }

    /// The confident brand + name match among the search's results (`ProductNameMatch`), or nil.
    public func searchProduct(brand: String, name: String) async throws -> ProductRecord? {
        guard let query = ProductNameMatch.query(brand: brand, name: name) else { return nil }
        let (data, response) = try await RetryPolicy.none.send(searchRequest(for: query), via: transport)
        guard response.isSuccess else { throw GreenCoreError.http(status: response.statusCode, body: data.bodyPreview) }
        let hits: [JSONValue]
        do {
            hits = try JSONDecoder().decode(JSONValue.self, from: data)["hits"]?.array ?? []
        } catch {
            throw GreenCoreError.decoding("Open Food Facts search \(query): \(error)")
        }
        let records = hits.compactMap { hit -> ProductRecord? in
            guard let code = hit["code"]?.string?.trimmedNonEmpty else { return nil }
            return OFFProductPayload.record(from: hit, gtin: code, sourceURL: Self.productPage(for: code), allBrands: true)
        }
        return ProductNameMatch.best(brand: brand, name: name, among: records)
    }

    /// `URLComponents` leaves "&" and "+" in query values as they are, which would cut "Salt & Vinegar" short.
    static let queryValueAllowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?#"))

    func searchRequest(for query: String) -> URLRequest {
        var components = URLComponents(url: searchURL.appending(path: "search"), resolvingAgainstBaseURL: false)!
        let items = [("q", query), ("page_size", String(Self.searchPageSize)), ("fields", Self.fields.joined(separator: ","))]
        components.percentEncodedQueryItems = items.map { name, value in
            URLQueryItem(name: name, value: value.addingPercentEncoding(withAllowedCharacters: Self.queryValueAllowed))
        }
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = searchTimeout
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    public func product(gtin: String) async throws -> ProductRecord? {
        guard let code = GTINDigits.normalized(gtin) else { return nil }
        let (data, response) = try await retry.send(request(for: code), via: transport)
        if response.statusCode == 404 { return nil }
        guard response.isSuccess else { throw GreenCoreError.http(status: response.statusCode, body: data.bodyPreview) }
        let payload: OFFProductPayload
        do {
            payload = try JSONDecoder().decode(OFFProductPayload.self, from: data)
        } catch {
            throw GreenCoreError.decoding("Open Food Facts product \(code): \(error)")
        }
        return payload.record(gtin: code, sourceURL: Self.productPage(for: code))
    }

    public func productImage(for record: ProductRecord) async -> Data? {
        guard let url = record.imageURL else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await transport.send(request), response.isSuccess, !data.isEmpty else { return nil }
        return data
    }

    func request(for code: String) -> URLRequest {
        var components = URLComponents(url: baseURL.appending(path: "api/v2/product/\(code).json"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "fields", value: Self.fields.joined(separator: ","))]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = timeout
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// Human-readable product page, used as the T1 source link.
    static func productPage(for code: String) -> URL {
        URL(string: "https://world.openfoodfacts.org/product/\(code)")!
    }
}
