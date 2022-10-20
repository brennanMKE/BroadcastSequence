import Foundation
import _Concurrency

// Goal: Allow multiple consumers of a source sequence which will send each element
// to each consumer while each consumer is observing the stream.

public actor BroadcastConsumer<Element: Sendable>: AsyncSequence, AsyncIteratorProtocol {
    public typealias Iterator = BroadcastConsumer<Element>
    typealias NextContinuation = CheckedContinuation<Element?, Never>
    typealias SendContinuation = CheckedContinuation<Void, Never>

    public let name: String?

    private let id = UUID()
    private var elements: [Element] = []
    private var nexts: [NextContinuation] = []
    private var sends: [SendContinuation] = []
    private var terminated: Bool = false

    public init(name: String? = nil) {
        self.name = name
    }

    public nonisolated func makeAsyncIterator() -> BroadcastConsumer<Element> {
        return self
    }

    public func next() async -> Element? {
        await withCheckedContinuation { (continuation: NextContinuation) in
            nexts.append(continuation)
            processNext()
        }
    }

    func send(element: Element?) async {
        guard let element = element else {
            terminateAll()
            return
        }

        await withTaskCancellationHandler {
            Task {
                await terminateAll()
            }
        } operation: {
            await withCheckedContinuation { (continuation: SendContinuation) in
                elements.append(element)
                sends.append(continuation)
                processNext()
            }
        }
    }

    private func terminateAll() {
        terminated = true
        while !sends.isEmpty {
            let send = sends.removeFirst()
            send.resume(returning: ())
        }
        while !nexts.isEmpty {
            let next = nexts.removeFirst()
            next.resume(returning: nil)
        }
    }

    private func processNext() {
        if terminated && !nexts.isEmpty {
            let next = nexts.removeFirst()
            next.resume(returning: nil)
            return
        }

        guard !elements.isEmpty,
              !sends.isEmpty,
              !nexts.isEmpty else {
            return
        }

        assert(!elements.isEmpty)
        assert(!nexts.isEmpty)
        assert(!sends.isEmpty)

        let element = elements.removeFirst()
        let send = sends.removeFirst()
        let next = nexts.removeFirst()

        next.resume(returning: element)
        send.resume(returning: ())
    }
}

extension BroadcastConsumer: Hashable {
    nonisolated public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: BroadcastConsumer<Element>, rhs: BroadcastConsumer<Element>) -> Bool {
        lhs.id == rhs.id
    }
}

public actor BroadcastSource<Element: Sendable> {
    private let source: AsyncStream<Element>
    private var consumers: Set<BroadcastConsumer<Element>> = []

    public init(source: AsyncStream<Element>) {
        self.source = source
        Task {
            await pipeElements()
        }
    }

    public func consume(name: String? = nil) -> BroadcastConsumer<Element> {
        let consumer = BroadcastConsumer<Element>(name: name)
        consumers.insert(consumer)
        return consumer
    }

    public func discard(consumer: BroadcastConsumer<Element>) {
        consumers.remove(consumer)
    }

    private func pipeElements() async {
        for await element in source {
            // send element to each consumer
            for consumer in consumers  {
                await consumer.send(element: element)
            }
        }

        // terminate each iterator
        for consumer in consumers  {
            await consumer.send(element: nil)
        }
    }

}
