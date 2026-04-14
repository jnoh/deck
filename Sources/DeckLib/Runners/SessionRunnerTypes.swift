import Foundation

public protocol SessionRunnerDelegate: AnyObject {
    func sessionDidStart(_ session: Session)
    func sessionDidStop(_ session: Session, exitCode: Int32?)
    func sessionDataReceived(_ session: Session, data: ArraySlice<UInt8>)
}

public enum SessionRunnerError: Error, CustomStringConvertible {
    case invalidState(String)

    public var description: String {
        switch self {
        case .invalidState(let msg):
            return msg
        }
    }
}
