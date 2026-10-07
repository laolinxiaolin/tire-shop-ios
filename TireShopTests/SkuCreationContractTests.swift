import XCTest
@testable import TireShop

final class SkuCreationContractTests: XCTestCase {
    func testCreationDelegatesCodesAndEmbeddedPlyHandlingToTheServer() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SkuCreationProtocol.self]
        let api = InventoryAPI(client: APIClient(session: URLSession(configuration: configuration)))

        for fixture in SkuCreationProtocol.fixtures {
            let input = SkuInput(brand: "Double Coin", model: "FD405", size: fixture.size,
                                 category: "TBR", position: "DRIVE", plyRating: fixture.ply,
                                 priceRetail: 270, priceWholesale: 245, priceFleet: 260)
            let result = try await api.createSku(input)
            XCTAssertEqual(result.sku, fixture.generatedCode)
            XCTAssertEqual(result.size, fixture.size, "Code generation must preserve the tire's dimensions")
            XCTAssertEqual(result.plyRating, fixture.ply)
            XCTAssertEqual(result.model, "FD405")
            XCTAssertEqual(result.id, "sku-created")
        }
    }

    func testAnExplicitSkuEditKeepsTheExistingCodeAndUsesOneModelField() throws {
        let patch = TireSkuPatchInput(sku: "EXISTING-LABEL", model: "Road Pattern")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(patch)) as? [String: Any])
        XCTAssertEqual(object["sku"] as? String, "EXISTING-LABEL")
        XCTAssertEqual(object["model"] as? String, "Road Pattern")
        XCTAssertNil(object["pattern"])
    }
}

/// Captured generator contract from the merged backend change. These are server
/// responses, not a second implementation of SKU generation inside the client.
private final class SkuCreationProtocol: URLProtocol {
    struct Fixture {
        let size: String
        let ply: String?
        let generatedCode: String
    }

    static let fixtures = [
        Fixture(size: "11R24.5-16PR", ply: "16", generatedCode: "11R24.5-16-FD405-DOUBLECOIN-D"),
        Fixture(size: "ST235/85R16-16", ply: "16", generatedCode: "ST235-85R16-16-FD405-DOUBLECOIN-D-2"),
        Fixture(size: "11R24.5-14PR", ply: "16", generatedCode: "11R24.5-14PR-16-FD405-DOUBLECOIN-D"),
        Fixture(size: "7.50-16", ply: "16", generatedCode: "7.50-16-16-FD405-DOUBLECOIN-D"),
        Fixture(size: "11R24.5-16PR", ply: nil, generatedCode: "11R24.5-16-FD405-DOUBLECOIN-D-3")
    ]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let url = try XCTUnwrap(request.url)
            guard request.httpMethod == "POST", url.path == "/api/inventory/skus" else {
                throw URLError(.unsupportedURL)
            }
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData()) as? [String: Any])
            // Omission, rather than a null/empty/manual SKU, invokes server generation.
            XCTAssertNil(body["sku"])
            XCTAssertNil(body["pattern"])
            XCTAssertEqual(body["brand"] as? String, "Double Coin")
            XCTAssertEqual(body["model"] as? String, "FD405")
            XCTAssertEqual(body["priceRetail"] as? Double, 270)
            XCTAssertEqual(body["priceWholesale"] as? Double, 245)
            XCTAssertEqual(body["priceFleet"] as? Double, 260)
            let fixture = try XCTUnwrap(Self.fixtures.first {
                $0.size == body["size"] as? String && $0.ply == body["plyRating"] as? String
            })
            var responseBody: [String: Any] = [
                "id": "sku-created", "sku": fixture.generatedCode,
                "brand": "Double Coin", "model": "FD405", "size": fixture.size,
                "category": "TBR", "position": "DRIVE", "priceRetail": "270.00",
                "priceWholesale": "245.00", "priceFleet": "260.00", "priceCost": "100.00",
                "reorderPoint": 2, "active": true, "inventory": []
            ]
            if let ply = fixture.ply { responseBody["plyRating"] = ply }
            let data = try JSONSerialization.data(withJSONObject: responseBody)
            let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 201, httpVersion: nil,
                                                       headerFields: ["Content-Type": "application/json"]))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private func bodyData() throws -> Data {
        if let data = request.httpBody { return data }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1_024)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: 1_024)
            guard count >= 0 else { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
