import XCTest
@_spi(Internal) @testable import ApolloAPI

/// Regression coverage for the `SelectionSet+Equatable.convertElements` precondition trap.
/// When a list field declared as `[Type?]` (nullable inner) contains an actual `null`
/// element, the equatable walker must preserve null slots without crashing.
final class SelectionSetEquatableTests: XCTestCase {

  // MARK: - Minimal mock scaffolding

  enum TestSchema: SchemaMetadata {
    static let configuration: any SchemaConfiguration.Type = TestSchemaConfiguration.self
    static func objectType(forTypename typename: String) -> Object? {
      Object(typename: typename, implementedInterfaces: [])
    }
  }

  enum TestSchemaConfiguration: SchemaConfiguration {
    static func cacheKeyInfo(for type: Object, object: ObjectData) -> CacheKeyInfo? { nil }
  }

  static let itemObject = Object(typename: "Item", implementedInterfaces: [])
  static let humanInterface = Interface(name: "Human", implementingObjects: [])

  class HumanFragment: RootSelectionSet, Hashable {
    typealias Schema = TestSchema
    typealias Fragments = NoFragments

    static var __parentType: any ParentType { humanInterface }
    static var __selections: [Selection] {[
      .field("items", [Item?].self)
    ]}
    static var __fulfilledFragments: [any SelectionSet.Type] { [HumanFragment.self] }

    var __data: DataDict
    required init(_dataDict: DataDict) { self.__data = _dataDict }

    class Item: RootSelectionSet, Hashable {
      typealias Schema = TestSchema
      typealias Fragments = NoFragments

      static var __parentType: any ParentType { itemObject }
      static var __selections: [Selection] {[
        .field("id", Int.self)
      ]}
      static var __fulfilledFragments: [any SelectionSet.Type] { [Item.self] }

      var __data: DataDict
      required init(_dataDict: DataDict) { self.__data = _dataDict }
    }
  }

  // MARK: - Helpers

  private func item(id: Int) -> AnyHashable {
    DataDict(
      data: ["__typename": "Item", "id": id],
      fulfilledFragments: [ObjectIdentifier(HumanFragment.Item.self)]
    )
  }

  private func makeHuman(items: [AnyHashable?]) -> HumanFragment {
    HumanFragment(_dataDict: DataDict(
      data: ["items": items as AnyHashable],
      fulfilledFragments: [ObjectIdentifier(HumanFragment.self)]
    ))
  }

  // MARK: - Tests

  /// Baseline: nullable-inner list with no actual nulls compares equal.
  func test_listOfNullableObjects_allPresent_areEqual() {
    let one = makeHuman(items: [item(id: 1), item(id: 2)])
    let two = makeHuman(items: [item(id: 1), item(id: 2)])

    XCTAssertEqual(one, two)
    XCTAssertEqual(one.hashValue, two.hashValue)
  }

  /// Regression: nullable-inner list containing a null element must not crash
  /// the equatable walker, and two identical such lists must compare equal.
  func test_listOfNullableObjects_withNullElement_sameShape_areEqual() {
    let one = makeHuman(items: [item(id: 1), DataDict._NullValue, item(id: 2)])
    let two = makeHuman(items: [item(id: 1), DataDict._NullValue, item(id: 2)])

    XCTAssertEqual(one, two)
    XCTAssertEqual(one.hashValue, two.hashValue)
  }

  /// Null slots must be position-sensitive: shifting the null position must
  /// produce inequality. Filtering nulls out would break this.
  func test_listOfNullableObjects_nullInDifferentPositions_areUnequal() {
    let one = makeHuman(items: [item(id: 1), DataDict._NullValue, item(id: 2)])
    let two = makeHuman(items: [DataDict._NullValue, item(id: 1), item(id: 2)])

    XCTAssertNotEqual(one, two)
  }
}
