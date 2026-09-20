import Foundation

public enum LlamaCPPEngineError: Error, Sendable, Equatable {
    case invalidModelURL
    case modelFileNotFound(URL)
    case modelAlreadyLoaded
    case modelNotLoaded
    case nativeModelLoadFailed(String)
    case nativeContextCreationFailed
    case tokenizationFailed
    case evalFailed(Int32)
    case thermalStateCritical
    case memoryPressureCritical
    case cancelled
}
