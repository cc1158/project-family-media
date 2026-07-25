import Foundation

public enum Loadable<Value: Equatable & Sendable>: Equatable, Sendable {
    case idle
    case loading
    case loaded(Value)
    case empty
    case failed(String)
}
