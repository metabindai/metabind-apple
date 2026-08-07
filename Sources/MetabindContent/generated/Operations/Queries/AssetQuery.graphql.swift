// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

public class AssetQuery: GraphQLQuery {
  public static let operationName: String = "AssetQuery"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    definition: .init(
      #"query AssetQuery($id: ID!) { asset(id: $id) { __typename ...AssetFields } }"#,
      fragments: [AssetFields.self]
    ))

  public var id: ID

  public init(id: ID) {
    self.id = id
  }

  public var __variables: Variables? { ["id": id] }

  public struct Data: MetabindContent.SelectionSet {
    public let __data: DataDict
    public init(_dataDict: DataDict) { __data = _dataDict }

    public static var __parentType: any ApolloAPI.ParentType { MetabindContent.Objects.Query }
    public static var __selections: [ApolloAPI.Selection] { [
      .field("asset", Asset?.self, arguments: ["id": .variable("id")]),
    ] }
    public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      AssetQuery.Data.self
    ] }

    public var asset: Asset? { __data["asset"] }

    /// Asset
    ///
    /// Parent Type: `Asset`
    public struct Asset: MetabindContent.SelectionSet {
      public let __data: DataDict
      public init(_dataDict: DataDict) { __data = _dataDict }

      public static var __parentType: any ApolloAPI.ParentType { MetabindContent.Objects.Asset }
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .fragment(AssetFields.self),
      ] }
      public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        AssetQuery.Data.Asset.self,
        AssetFields.self
      ] }

      public var id: MetabindContent.ID { __data["id"] }
      public var name: String { __data["name"] }
      public var type: String { __data["type"] }
      public var url: String { __data["url"] }
      public var size: Int { __data["size"] }
      public var width: Int? { __data["width"] }
      public var height: Int? { __data["height"] }
      public var tags: [String] { __data["tags"] }
      public var updatedAt: MetabindContent.DateTime { __data["updatedAt"] }

      public struct Fragments: FragmentContainer {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public var assetFields: AssetFields { _toFragment() }
      }
    }
  }
}
