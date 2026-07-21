// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

public class TagQuery: GraphQLQuery {
  public static let operationName: String = "TagQuery"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    definition: .init(
      #"query TagQuery($id: ID!) { tag(id: $id) { __typename ...TagFields } }"#,
      fragments: [TagFields.self]
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
      .field("tag", Tag?.self, arguments: ["id": .variable("id")]),
    ] }

    public var tag: Tag? { __data["tag"] }

    /// Tag
    ///
    /// Parent Type: `Tag`
    public struct Tag: MetabindContent.SelectionSet {
      public let __data: DataDict
      public init(_dataDict: DataDict) { __data = _dataDict }

      public static var __parentType: any ApolloAPI.ParentType { MetabindContent.Objects.Tag }
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .fragment(TagFields.self),
      ] }

      public var id: MetabindContent.ID { __data["id"] }
      public var name: String { __data["name"] }
      public var slug: String { __data["slug"] }

      public struct Fragments: FragmentContainer {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public var tagFields: TagFields { _toFragment() }
      }
    }
  }
}
