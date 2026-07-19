final class DeferredConstruction<Value> {
    private let factory: () -> Value
    private var storedValue: Value?

    init(_ factory: @escaping () -> Value) {
        self.factory = factory
    }

    var isConstructed: Bool { storedValue != nil }

    var value: Value {
        if let storedValue { return storedValue }
        let created = factory()
        storedValue = created
        return created
    }
}

final class ExpandableConstruction<Value: AnyObject> {
    private let factory: () -> Value
    private(set) var expandedValue: Value?

    init(_ factory: @escaping () -> Value) {
        self.factory = factory
    }

    var isExpanded: Bool { expandedValue != nil }

    func expand() -> Value {
        if let expandedValue { return expandedValue }
        let created = factory()
        expandedValue = created
        return created
    }

    func collapse() {
        expandedValue = nil
    }
}
