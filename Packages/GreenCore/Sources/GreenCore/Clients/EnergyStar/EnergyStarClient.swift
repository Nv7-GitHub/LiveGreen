import Foundation

/// T1 appliance lookup against ENERGY STAR certified-product datasets on data.energystar.gov via
/// Socrata SODA queries (spec §5.4): brand + model number → on-mode W, standby W, annual kWh.
public struct EnergyStarClient: ApplianceDatabase {
    public var baseURL: URL
    /// Optional Socrata app token (`ENERGYSTAR_APP_TOKEN`) for higher rate limits.
    public var appToken: String?
    public var datasets: [EnergyStarDataset]
    public var timeout: Double
    public var retry: RetryPolicy
    let transport: any HTTPTransport

    static let rowLimit = 50

    public init(appToken: String? = nil, baseURL: URL = URL(string: "https://data.energystar.gov")!,
                datasets: [EnergyStarDataset] = EnergyStarDataset.all, timeout: Double = 12,
                retry: RetryPolicy = .default, transport: any HTTPTransport = URLSessionTransport()) {
        self.appToken = appToken
        self.baseURL = baseURL
        self.datasets = datasets
        self.timeout = timeout
        self.retry = retry
        self.transport = transport
    }

    public func appliance(brand: String, model: String) async throws -> ApplianceRecord? {
        try await appliance(brand: brand, model: model, deviceType: nil)
    }

    /// Queries the datasets for `deviceType` (all configured datasets when nil or unmatched) concurrently
    /// and returns the best-matching record. Throws only if every dataset query failed.
    public func appliance(brand: String, model: String, deviceType: String?) async throws -> ApplianceRecord? {
        let candidates = deviceType.map { type in
            datasets.filter { $0.deviceTypes.contains(type.lowercased()) }
        }.flatMap { $0.isEmpty ? nil : $0 } ?? datasets
        guard let brandKey = Self.brandKey(brand), ModelNumberMatcher.likePattern(for: model) != nil else { return nil }

        var matches: [(index: Int, score: ModelNumberMatcher.Score, record: ApplianceRecord)] = []
        var failures: [any Error] = []
        await withTaskGroup(of: (Int, Result<(ModelNumberMatcher.Score, ApplianceRecord)?, any Error>).self) { group in
            for (index, dataset) in candidates.enumerated() {
                group.addTask {
                    do {
                        return (index, .success(try await bestMatch(in: dataset, brandKey: brandKey, model: model)))
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }
            for await (index, result) in group {
                switch result {
                case .success(let match?): matches.append((index, match.0, match.1))
                case .success(nil): break
                case .failure(let error): failures.append(error)
                }
            }
        }
        if matches.isEmpty, failures.count == candidates.count, let first = failures.first { throw first }
        // Highest score wins; ties go to the earlier dataset so results are deterministic.
        return matches.min { ($0.score, -$0.index) > ($1.score, -$1.index) }?.record
    }

    func bestMatch(in dataset: EnergyStarDataset, brandKey: String, model: String) async throws
        -> (ModelNumberMatcher.Score, ApplianceRecord)? {
        guard let request = request(for: dataset, brandKey: brandKey, model: model) else { return nil }
        let (data, response) = try await retry.send(request, via: transport)
        guard response.isSuccess else { throw GreenCoreError.http(status: response.statusCode, body: data.bodyPreview) }
        let rows: [JSONValue]
        do {
            rows = try JSONDecoder().decode([JSONValue].self, from: data)
        } catch {
            throw GreenCoreError.decoding("ENERGY STAR \(dataset.id): \(error)")
        }
        return rows
            .map { row in (ModelNumberMatcher.bestScore(query: model, candidates: dataset.modelColumns.compactMap { row[$0]?.string }), row) }
            .filter { $0.0 > .none }
            .max { $0.0 < $1.0 }
            .map { ($0.0, record(from: $0.1, dataset: dataset, fallbackBrand: brandKey, fallbackModel: model)) }
    }

    func request(for dataset: EnergyStarDataset, brandKey: String, model: String) -> URLRequest? {
        guard let pattern = ModelNumberMatcher.likePattern(for: model) else { return nil }
        let modelClause = dataset.modelColumns
            .map { "upper(\($0)) like '\(Self.escape(pattern))'" }
            .joined(separator: " OR ")
        let whereClause = "upper(brand_name) like '%\(Self.escape(brandKey))%' AND (\(modelClause))"
        var components = URLComponents(url: baseURL.appending(path: "resource/\(dataset.id).json"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "$where", value: whereClause),
            URLQueryItem(name: "$order", value: "pd_id"),
            URLQueryItem(name: "$limit", value: String(Self.rowLimit)),
        ]
        // A literal "+" (e.g. "BLACK+DECKER") would otherwise be read as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let appToken = appToken?.trimmedNonEmpty { request.setValue(appToken, forHTTPHeaderField: "X-App-Token") }
        return request
    }

    func record(from row: JSONValue, dataset: EnergyStarDataset, fallbackBrand: String, fallbackModel: String) -> ApplianceRecord {
        let pdID = row["pd_id"]?.string ?? ""
        var source = URLComponents(url: baseURL.appending(path: "resource/\(dataset.id).json"), resolvingAgainstBaseURL: false)!
        source.queryItems = pdID.isEmpty ? nil : [URLQueryItem(name: "pd_id", value: pdID)]
        return ApplianceRecord(
            brand: row["brand_name"]?.string ?? fallbackBrand,
            model: row["model_number"]?.string ?? row["model_name"]?.string ?? fallbackModel,
            productType: dataset.productType,
            onModeWatts: dataset.onModeColumn.flatMap { row[$0]?.double },
            standbyWatts: dataset.standbyColumns.lazy.compactMap { row[$0]?.double }.first,
            annualKWh: dataset.annualKWhColumn.flatMap { row[$0]?.double },
            datasetName: dataset.name,
            sourceURL: source.url ?? baseURL)
    }

    /// First word of the brand, uppercased ("Samsung Electronics" → "SAMSUNG").
    static func brandKey(_ brand: String) -> String? {
        brand.uppercased().split(whereSeparator: { $0.isWhitespace }).first.map(String.init)?.trimmedNonEmpty
    }

    /// SoQL string literal escaping.
    static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }
}
