import Foundation

/// T1 packaged-goods records from Open Food Facts (spec §5.4):
/// `GET https://world.openfoodfacts.org/api/v2/product/{gtin}.json?fields=…`.
public struct OpenFoodFactsClient: ProductDatabase {
    public static let userAgent = "LiveGreen/1.0 (HackHarvard)"
    static let fields = ["code", "product_name", "product_name_en", "brands", "product_quantity",
                         "product_quantity_unit", "quantity", "serving_quantity", "serving_quantity_unit", "categories_tags", "ecoscore_data", "packagings"]

    public var baseURL: URL
    public var timeout: Double
    public var retry: RetryPolicy
    let transport: any HTTPTransport

    public init(baseURL: URL = URL(string: "https://world.openfoodfacts.org")!, timeout: Double = 10,
                retry: RetryPolicy = .default, transport: any HTTPTransport = URLSessionTransport()) {
        self.baseURL = baseURL
        self.timeout = timeout
        self.retry = retry
        self.transport = transport
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
