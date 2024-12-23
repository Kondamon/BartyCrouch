//
//  ErrorDescription.swift
//
//
//  Created by Christian Elbe on 23.12.24.
//

import Foundation
import Microya

/// Enhanced error descriptions for API calls
extension ApiError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .noResponseReceived(let error):
            if let error = error {
                return "No response received. Underlying error: \(error.localizedDescription)"
            } else {
                return "No response received. No additional error information."
            }

        case .noDataInResponse(let statusCode):
            return "No data in response. Status code: \(statusCode)."

        case .responseDataConversionFailed(let type, let error):
            return "Failed to convert response data to type '\(type)'. Error: \(error.localizedDescription)"

        case .clientError(let statusCode, let clientError):
            if let clientError = clientError {
                return "Client error. Status code: \(statusCode). Error details: \(clientError)"
            } else {
                return "Client error. Status code: \(statusCode). No additional error information."
            }

        case .serverError(let statusCode):
            return "Server error. Status code: \(statusCode)."

        case .unexpectedStatusCode(let statusCode):
            return "Unexpected status code: \(statusCode)."

        case .unexpectedResponseType(let response):
            return "Unexpected response type: \(type(of: response)). Response: \(response)."

        case .emptyMockedResponse:
            return "Mocked behavior was set, but no mocked response was provided."
        }
    }
}
