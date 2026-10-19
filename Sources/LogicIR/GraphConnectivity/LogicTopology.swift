import LogicKernelCore

internal enum LogicTopology {
    static func order<Index>(nodeCount: Int, edges: borrowing [(Int, Int)],
                             makeIndex: (Int) -> Index, context: inout LogicKernelContext)
        throws(LogicKernelError) -> [Index] {
        guard nodeCount >= 0, nodeCount < Int.max else { throw .invalidModel("Topology capacity overflow") }
        var bytes: UInt64 = 0
        for (count, stride) in [(nodeCount + 1, 4 * MemoryLayout<Int>.stride),
                                (edges.count, MemoryLayout<Int>.stride)] {
            let size = UInt64(count).multipliedReportingOverflow(by: UInt64(stride))
            let total = bytes.addingReportingOverflow(size.partialValue)
            guard !size.overflow, !total.overflow else { throw .invalidModel("Topology storage overflow") }
            bytes = total.partialValue
        }
        let reservation = try context.reserveStorage(byteCount: bytes)
        let result: [Index]
        do { result = try traverse(nodeCount: nodeCount, edges: edges, makeIndex: makeIndex, context: &context) }
        catch { try context.releaseStorage(reservation); throw error }
        try context.releaseStorage(reservation)
        return result
    }

    private static func traverse<Index>(nodeCount: Int, edges: borrowing [(Int, Int)],
                                        makeIndex: (Int) -> Index, context: inout LogicKernelContext)
        throws(LogicKernelError) -> [Index] {
        var indegree = [Int](repeating: 0, count: nodeCount)
        var offsets = [Int](repeating: 0, count: nodeCount + 1)
        for index in edges.indices {
            try context.charge(.workUnits)
            let (source, destination) = edges[index]
            guard source >= 0, source < nodeCount, destination >= 0, destination < nodeCount else {
                throw .invalidModel("Topology edge outside graph")
            }
            indegree[destination] += 1; offsets[source + 1] += 1
        }
        for index in 0..<nodeCount { try context.charge(.workUnits); offsets[index + 1] += offsets[index] }
        var cursor = offsets
        var destinations = [Int](repeating: 0, count: edges.count)
        for index in edges.indices {
            try context.charge(.workUnits)
            let (source, destination) = edges[index]
            destinations[cursor[source]] = destination; cursor[source] += 1
        }
        // Queue contains indices, while result storage belongs to the caller reservation.
        var result: [Index] = []; result.reserveCapacity(nodeCount)
        var queue: [Int] = []; queue.reserveCapacity(nodeCount)
        for index in 0..<nodeCount where indegree[index] == 0 { queue.append(index) }
        var head = 0
        while head < queue.count {
            try context.charge(.workUnits)
            let source = queue[head]; head += 1; result.append(makeIndex(source))
            for offset in offsets[source]..<offsets[source + 1] {
                try context.charge(.workUnits)
                let destination = destinations[offset]; indegree[destination] -= 1
                if indegree[destination] == 0 { queue.append(destination) }
            }
        }
        guard result.count == nodeCount else { throw .invalidModel("Combinational or transparent latch cycle") }
        return result
    }
}
