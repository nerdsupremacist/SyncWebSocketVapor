
import Vapor
import Sync
import OpenCombineShim
@_exported import NIO

extension RoutesBuilder {
    @discardableResult
    public func syncObjectOverWebSocket<Value : SyncableObject>(
        _ path: PathComponent...,
        maxFrameSize: WebSocketMaxFrameSize = .`default`,
        shouldUpgrade: @escaping ((Request) -> EventLoopFuture<HTTPHeaders?>) = {
            $0.eventLoop.makeSucceededFuture([:])
        },
        codingContext: EventCodingContext = JSONEventCodingContext(),
        value getValue: @escaping (Request) throws -> Value
    ) -> Route {
        return syncObjectOverWebSocket(path,
                                       maxFrameSize: maxFrameSize,
                                       shouldUpgrade: shouldUpgrade,
                                       codingContext: codingContext,
                                       value: getValue)
    }

    @discardableResult
    public func syncObjectOverWebSocket<Value : SyncableObject>(
        _ path: [PathComponent],
        maxFrameSize: WebSocketMaxFrameSize = .`default`,
        shouldUpgrade: @escaping ((Request) -> EventLoopFuture<HTTPHeaders?>) = {
            $0.eventLoop.makeSucceededFuture([:])
        },
        codingContext: EventCodingContext = JSONEventCodingContext(),
        value getValue: @escaping (Request) throws -> Value
    ) -> Route {
        return syncObjectOverWebSocket(path, maxFrameSize: maxFrameSize, shouldUpgrade: shouldUpgrade, codingContext: codingContext) { request in
            return request.eventLoop.tryFuture {
                return try getValue(request)
            }
        }
    }
}

extension RoutesBuilder {
    @discardableResult
    public func syncObjectOverWebSocket<Value : SyncableObject>(
        _ path: PathComponent...,
        maxFrameSize: WebSocketMaxFrameSize = .`default`,
        shouldUpgrade: @escaping ((Request) -> EventLoopFuture<HTTPHeaders?>) = {
            $0.eventLoop.makeSucceededFuture([:])
        },
        codingContext: EventCodingContext = JSONEventCodingContext(),
        value getValue: @escaping (Request) async throws -> Value
    ) -> Route {
        return syncObjectOverWebSocket(path,
                                       maxFrameSize: maxFrameSize,
                                       shouldUpgrade: shouldUpgrade,
                                       codingContext: codingContext,
                                       value: getValue)
    }

    @discardableResult
    public func syncObjectOverWebSocket<Value : SyncableObject>(
        _ path: [PathComponent],
        maxFrameSize: WebSocketMaxFrameSize = .`default`,
        shouldUpgrade: @escaping ((Request) -> EventLoopFuture<HTTPHeaders?>) = {
            $0.eventLoop.makeSucceededFuture([:])
        },
        codingContext: EventCodingContext = JSONEventCodingContext(),
        value getValue: @escaping (Request) async throws -> Value
    ) -> Route {
        return syncObjectOverWebSocket(path,
                                       maxFrameSize: maxFrameSize,
                                       shouldUpgrade: shouldUpgrade,
                                       codingContext: codingContext) { request -> EventLoopFuture<Value> in

            let promise = request.eventLoop.makePromise(of: Value.self)
            promise.completeWithTask {
                try await getValue(request)
            }
            return promise.futureResult
        }
    }
}


extension RoutesBuilder {
    @discardableResult
    public func syncObjectOverWebSocket<Value : SyncableObject>(
        _ path: PathComponent...,
        maxFrameSize: WebSocketMaxFrameSize = .`default`,
        shouldUpgrade: @escaping ((Request) -> EventLoopFuture<HTTPHeaders?>) = {
            $0.eventLoop.makeSucceededFuture([:])
        },
        codingContext: EventCodingContext = JSONEventCodingContext(),
        value getValue: @escaping (Request) -> EventLoopFuture<Value>
    ) -> Route {
        return syncObjectOverWebSocket(path,
                                       maxFrameSize: maxFrameSize,
                                       shouldUpgrade: shouldUpgrade,
                                       codingContext: codingContext,
                                       value: getValue)
    }

    @discardableResult
    public func syncObjectOverWebSocket<Value : SyncableObject>(
        _ path: [PathComponent],
        maxFrameSize: WebSocketMaxFrameSize = .`default`,
        shouldUpgrade: @escaping ((Request) -> EventLoopFuture<HTTPHeaders?>) = {
            $0.eventLoop.makeSucceededFuture([:])
        },
        codingContext: EventCodingContext = JSONEventCodingContext(),
        value getValue: @escaping (Request) -> EventLoopFuture<Value>
    ) -> Route {
        return webSocket(path, maxFrameSize: maxFrameSize, shouldUpgrade: shouldUpgrade) { request, webSocket in
            getValue(request).whenComplete { result in
                switch result {
                case .success(let value):
                    do {
                        let initialData = try codingContext.encode(value)
                        let connection = WebSocketServerConnection(webSocket: webSocket, codingContext: codingContext)
                        webSocket.send(raw: initialData, opcode: .binary)
                        let manager = value.sync(with: connection)
                        webSocket.onClose.whenSuccess { [manager] _ in
                            _ = manager
                        }
                    } catch {
                        _ = webSocket.close(code: .unexpectedServerError)
                    }
                case .failure:
                    _ = webSocket.close(code: .unexpectedServerError)
                }
            }
        }
    }
}

private class WebSocketServerConnection: ProducerConnection {
    let webSocket: WebSocket
    let codingContext: EventCodingContext

    @Published
    private(set) var isConnected: Bool

    var isConnectedPublisher: AnyPublisher<Bool, Never> {
        return $isConnected.eraseToAnyPublisher()
    }

    private let subject = PassthroughSubject<Data, Never>()

    init(webSocket: WebSocket, codingContext: EventCodingContext) {
        self.webSocket = webSocket
        self.codingContext = codingContext
        self.isConnected = true
        webSocket.onBinary { [weak self] _, buffer in
            let length = buffer.readableBytes
            guard let data = buffer.getData(at: 0, length: length) else { return }
            self?.subject.send(data)
        }
        webSocket.onText { [weak self] _, string in
            guard let data = string.data(using: .utf8) else { return }
            self?.subject.send(data)
        }
        webSocket.onClose.whenComplete { [weak self] _ in
            self?.isConnected = false
        }
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
