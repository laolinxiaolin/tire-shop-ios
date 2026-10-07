import Foundation

enum CustomerTaxSaveResult {
    case reloaded(Customer)
    case needsCustomerReload
}

struct CustomerTaxAPI {
    var client = APIClient.shared

    func details(customerId: String) async throws -> CustomerTaxDetails {
        try await client.request("/customers/\(customerId)/tax-rate")
    }

    func saveOverride(customerId: String, body: CustomerTaxOverrideInput) async throws -> CustomerTaxSaveResult {
        // The mutation returns only the customer row, without profile relations.
        let _: EmptyResponse = try await client.request("/customers/\(customerId)/tax-rate", method: "PATCH", body: body)
        do {
            return .reloaded(try await reloadCustomer(customerId: customerId))
        } catch {
            // The write has succeeded. Recovery must retry only the read.
            return .needsCustomerReload
        }
    }

    func reloadCustomer(customerId: String) async throws -> Customer {
        try await CustomersAPI(client: client).get(id: customerId)
    }

    func reviewAddress(customerId: String, body: CustomerAddressReviewInput) async throws {
        let _: EmptyResponse = try await client.request(
            "/customers/\(customerId)/tax-resolution/review", method: "POST", body: body
        )
    }
}
