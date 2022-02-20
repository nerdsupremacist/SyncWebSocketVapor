
import Vapor
import Sync
import Combine

extension RoutesBuilder {
    @discardableResult
    public func syncObjectOverWebSocket<Value : SyncedObject>(
        _ path: PathComponent...,
        maxFrameSize: WebSocketMaxFrameSize = .`default`,
        shouldUpgrade: @escaping ((Request) -> EventLoopFuture<HTTPHeaders?>) = {
            $0.eventLoop.makeSucceededFuture([:])
        },
        codingContext: EventCodingContext = JSONEventCodingContext(),
        value getValue: @escaping (Request) -> Value
    ) -> Route {
        return syncObjectOverWebSocket(path,
                                       maxFrameSize: maxFrameSize,
                                       shouldUpgrade: shouldUpgrade,
                                       codingContext: codingContext,
                                       value: getValue)
    }

    @discardableResult
    public func syncObjectOverWebSocket<Value : SyncedObject>(
        _ path: [PathComponent],
        maxFrameSize: WebSocketMaxFrameSize = .`default`,
        shouldUpgrade: @escaping ((Request) -> EventLoopFuture<HTTPHeaders?>) = {
            $0.eventLoop.makeSucceededFuture([:])
        },
        codingContext: EventCodingContext = JSONEventCodingContext(),
        value getValue: @escaping (Request) -> Value
    ) -> Route {
        return webSocket(path, maxFrameSize: maxFrameSize, shouldUpgrade: shouldUpgrade) { request, webSocket in
            do {
                let value = getValue(request)
                let initialData = try codingContext.encode(value)
                let connection = WebSocketServerConnection(webSocket: webSocket, codingContext: codingContext)
                webSocket.send(raw: initialData, opcode: .binary)
                let manager = value.manager(with: connection)
                webSocket.onClose.whenSuccess { [manager] _ in
                    _ = manager
                }
            } catch {

            }
        }
    }
}

private class WebSocketServerConnection: ProducerConnection {
    let webSocket: WebSocket
    let codingContext: EventCodingContext

    private let subject = PassthroughSubject<Data, Never>()

    init(webSocket: WebSocket, codingContext: EventCodingContext) {
        self.webSocket = webSocket
        self.codingContext = codingContext
        webSocket.onBinary { [weak self] _, buffer in
            let length = buffer.readableBytes
            guard let data = buffer.getData(at: 0, length: length) else { return }
            self?.subject.send(data)
        }
        webSocket.onText { [weak self] _, string in
            guard let data = string.data(using: .utf8) else { return }
            self?.subject.send(data)
        }
    }

    var isConnected: Bool {
        return !webSocket.isClosed
    }

    func disconnect() {
        _ = webSocket.close()
    }

    func send(data: Data) {
        webSocket.send(raw: data, opcode: .binary)
    }

    func receive() -> AnyPublisher<Data, Never> {
        return subject.eraseToAnyPublisher()
    }
}
