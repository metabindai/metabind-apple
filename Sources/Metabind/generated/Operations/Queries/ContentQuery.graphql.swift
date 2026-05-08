// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

public class ContentQuery: GraphQLQuery {
  public static let operationName: String = "ContentQuery"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    definition: .init(
      #"query ContentQuery($id: ID!) { content(id: $id) { __typename ...ContentFields } }"#,
      fragments: [ContentFields.self, ResolvedPackageRefFields.self]
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
      .field("content", Content?.self, arguments: ["id": .variable("id")]),
    ] }

    public var content: Content? { __data["content"] }

    /// Content
    ///
    /// Parent Type: `Content`
    public struct Content: Metabind.SelectionSet {
      public let __data: DataDict
      public init(_dataDict: DataDict) { __data = _dataDict }

      public static var __parentType: any ApolloAPI.ParentType { Metabind.Objects.Content }
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .fragment(ContentFields.self),
      ] }

      public var id: Metabind.ID { __data["id"] }
      public var typeId: Metabind.ID { __data["typeId"] }
      public var packageVersion: String { __data["packageVersion"] }
      public var name: String { __data["name"] }
      public var content: String { __data["content"] }
      public var compiled: String { __data["compiled"] }
      public var tags: [String] { __data["tags"] }
      public var locale: String? { __data["locale"] }
      public var createdAt: Metabind.DateTime { __data["createdAt"] }
      public var updatedAt: Metabind.DateTime { __data["updatedAt"] }
      public var lastPublishedVersion: Int? { __data["lastPublishedVersion"] }
      public var resolvedRef: ResolvedRef { __data["resolvedRef"] }

      public struct Fragments: FragmentContainer {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public var contentFields: ContentFields { _toFragment() }
      }

      public typealias ResolvedRef = ContentFields.ResolvedRef
    }
  }
}
