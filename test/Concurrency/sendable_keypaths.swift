// RUN: %target-typecheck-verify-swift -enable-experimental-feature InferSendableFromCaptures -strict-concurrency=complete

// REQUIRES: concurrency
// REQUIRES: asserts

class NonSendable : Hashable {
  var data: Int

  init(data: Int = 42) {
    self.data = data
  }

  init(data: [Int]) {
    self.data = data.first!
  }

  static func == (x: NonSendable, y: NonSendable) -> Bool { false }
  func hash(into hasher: inout Hasher) {}
}

final class CondSendable<T> : Hashable {
  init(_: T) {}
  init(_: Int) {}
  init(_: T, other: T = 42) {}
  init<Q>(_: [Q] = []) {}

  static func == (x: CondSendable, y: CondSendable) -> Bool { false }
  func hash(into hasher: inout Hasher) {}
}

extension CondSendable : Sendable where T: Sendable {
}

// Test forming sendable key paths without context
do {
  class K {
    var data: String = ""

    subscript<T>(_: T) -> Bool {
      get { false }
    }

    subscript<Q>(_: Int, _: Q) -> Int {
      get { 42 }
      set {}
    }
  }

  let kp = \K.data // Marked as  `& Sendable`

  let _: KeyPath<K, String> = kp // Ok
  let _: KeyPath<K, String> & Sendable = kp // Ok

  func test<V>(_: KeyPath<K, V> & Sendable) {
  }

  test(kp) // Ok

  let nonSendableKP = \K.[NonSendable()]

  let _: KeyPath<K, Bool> = \.[NonSendable()] // ok
  let _: KeyPath<K, Bool> & Sendable = \.[NonSendable()] // expected-warning {{type 'KeyPath<K, Bool>' does not conform to the 'Sendable' protocol}}
  let _: KeyPath<K, Int> & Sendable = \.[42, NonSendable(data: [-1, 0, 1])] // expected-warning {{type 'ReferenceWritableKeyPath<K, Int>' does not conform to the 'Sendable' protocol}}
  let _: KeyPath<K, Int> & Sendable = \.[42, -1] // Ok

  test(nonSendableKP) // expected-warning {{type 'KeyPath<K, Bool>' does not conform to the 'Sendable' protocol}}
}

// Test using sendable and non-sendable key paths.
do {
  class V {
    var i: Int = 0

    subscript<T>(_: T) -> Int {
      get { 42 }
    }

    subscript<Q>(_: Int, _: Q) -> Int {
      get { 42 }
      set {}
    }
  }

  func testSendableKP<T, U>(v: T, _ kp: any KeyPath<T, U> & Sendable) {}
  func testSendableFn<T, U>(v: T, _: @Sendable (T) -> U) {}

  func testNonSendableKP<T, U>(v: T, _ kp: KeyPath<T, U>) {}
  func testNonSendableFn<T, U>(v: T, _ kp: (T) -> U) {}

  let v = V()

  testSendableKP(v: v, \.i) // Ok
  testSendableFn(v: v, \.i) // Ok

  testSendableKP(v: v, \.[42]) // Ok
  testSendableFn(v: v, \.[42]) // Ok

  testSendableKP(v: v, \.[NonSendable()]) // expected-warning {{type 'KeyPath<V, Int>' does not conform to the 'Sendable' protocol}}
  // Note that there is no warning here because the key path is wrapped in a closure and not captured by it: `{ $0[keyPath: \.[NonSendable()]] }`
  testSendableFn(v: v, \.[NonSendable()]) // Ok

  testNonSendableKP(v: v, \.[NonSendable()]) // Ok
  testNonSendableFn(v: v, \.[NonSendable()]) // Ok

  let _: @Sendable (V) -> Int = \.[NonSendable()] // Ok

  let _: KeyPath<V, Int> & Sendable = \.[42, CondSendable(NonSendable(data: [1, 2, 3]))]
  // expected-warning@-1 {{type 'ReferenceWritableKeyPath<V, Int>' does not conform to the 'Sendable' protocol}}
  let _: KeyPath<V, Int> & Sendable = \.[42, CondSendable(42)] // Ok

  struct Root {
    let v: V
  }

  testSendableKP(v: v, \.[42, CondSendable(NonSendable(data: [1, 2, 3]))])
  // expected-warning@-1 {{type 'ReferenceWritableKeyPath<V, Int>' does not conform to the 'Sendable' protocol}}
  testSendableFn(v: v, \.[42, CondSendable(NonSendable(data: [1, 2, 3]))]) // Ok
  testSendableKP(v: v, \.[42, CondSendable(42)]) // Ok

  let nonSendable = NonSendable()
  testSendableKP(v: v, \.[42, CondSendable(nonSendable)])
  // expected-warning@-1 {{type 'ReferenceWritableKeyPath<V, Int>' does not conform to the 'Sendable' protocol}}

  // TODO: This should be diagnosed by the isolation checker because implicitly synthesized closures captures a non-Sendable value.
  testSendableFn(v: v, \.[42, CondSendable(nonSendable)])
}

// @dynamicMemberLookup with Sendable requirement
do {
  @dynamicMemberLookup
  struct Test<T> {
    var obj: T

    subscript<U>(dynamicMember member: KeyPath<T, U> & Sendable) -> U {
      get { obj[keyPath: member] }
    }
  }

  _ = Test(obj: "Hello").utf8.count // Ok
}
