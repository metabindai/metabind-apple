// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

public class ContentTypeQuery: GraphQLQuery {
  public static let operationName: String = "ContentTypeQuery"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    definition: .init(
      #"query ContentTypeQuery($id: ID!) { contentType(id: $id) { __typename ...ContentTypeFields } }"#,
      fragments: [ContentTypeFields.self]
    ))

  public var id: ID

  public init(id: ID) {
    self.id = id
  }

  public var __variables: Variables? { ["id": id] }

  public struct Data: Metabind.SelectionSet {
    public let __data: DataDict
    public init(_dataDict: DataDict) { __data = _dataDict }

    public static var __parentType: any ApolloAPI.ParentType { Metabind.Objects.Query }
    public static var __selections: [ApolloAPI.Selection] { [
      .field("contentType", ContentType?.self, arguments: ["id": .variable("id")]),
    ] }

    public var contentType: ContentType? { __data["contentType"] }

    /// ContentType
    ///
    /// Parent Type: `ContentType`
    public struct ContentType: Metabind.SelectionSet {
      public let __data: DataDict
      public init(_dataDict: DataDict) { __data = _dataDict }

      public static var __parentType: any ApolloAPI.ParentType { Metabind.Objects.ContentType }
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .fragment(ContentTypeFields.self),
      ] }

      public var id: Metabind.ID { __data["id"] }
      public var name: String { __data["name"] }
      public var packageVersion: String { __data["packageVersion"] }
      public var schema: String { __data["schema"] }
      public var updatedAt: Metabind.DateTime { __data["updatedAt"] }

      public struct Fragments: FragmentContainer {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public var contentTypeFields: ContentTypeFields { _toFragment() }
      }
    }
  }
}
