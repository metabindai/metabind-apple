// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

public class ContentUpdatedSubscription: GraphQLSubscription {
  public static let operationName: String = "ContentUpdatedSubscription"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    definition: .init(
      #"subscription ContentUpdatedSubscription($id: ID!) { contentUpdated(id: $id) { __typename contentId content { __typename ...ContentFields } resolvedRef { __typename ...ResolvedPackageRefFields } action timestamp } }"#,
      fragments: [ContentFields.self, ResolvedPackageRefFields.self]
    ))

  public var id: ID

  public init(id: ID) {
    self.id = id
  }

  public var __variables: Variables? { ["id": id] }

  public struct Data: MetabindContent.SelectionSet {
    public let __data: DataDict
    public init(_dataDict: DataDict) { __data = _dataDict }

    public static var __parentType: any ApolloAPI.ParentType { MetabindContent.Objects.Subscription }
    public static var __selections: [ApolloAPI.Selection] { [
      .field("contentUpdated", ContentUpdated.self, arguments: ["id": .variable("id")]),
    ] }
    public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      ContentUpdatedSubscription.Data.self
    ] }

    public var contentUpdated: ContentUpdated { __data["contentUpdated"] }

    /// ContentUpdated
    ///
    /// Parent Type: `ContentUpdate`
    public struct ContentUpdated: MetabindContent.SelectionSet {
      public let __data: DataDict
      public init(_dataDict: DataDict) { __data = _dataDict }

      public static var __parentType: any ApolloAPI.ParentType { MetabindContent.Objects.ContentUpdate }
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .field("contentId", MetabindContent.ID.self),
        .field("content", Content?.self),
        .field("resolvedRef", ResolvedRef.self),
        .field("action", String.self),
        .field("timestamp", MetabindContent.DateTime.self),
      ] }
      public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        ContentUpdatedSubscription.Data.ContentUpdated.self
      ] }

      public var contentId: MetabindContent.ID { __data["contentId"] }
      public var content: Content? { __data["content"] }
      public var resolvedRef: ResolvedRef { __data["resolvedRef"] }
      public var action: String { __data["action"] }
      public var timestamp: MetabindContent.DateTime { __data["timestamp"] }

      /// ContentUpdated.Content
      ///
      /// Parent Type: `Content`
      public struct Content: MetabindContent.SelectionSet {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public static var __parentType: any ApolloAPI.ParentType { MetabindContent.Objects.Content }
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .fragment(ContentFields.self),
        ] }
        public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          ContentUpdatedSubscription.Data.ContentUpdated.Content.self,
          ContentFields.self
        ] }

        public var id: MetabindContent.ID { __data["id"] }
        public var typeId: MetabindContent.ID { __data["typeId"] }
        public var packageVersion: String { __data["packageVersion"] }
        public var name: String { __data["name"] }
        public var content: String { __data["content"] }
        public var compiled: String { __data["compiled"] }
        public var tags: [String] { __data["tags"] }
        public var locale: String? { __data["locale"] }
        public var createdAt: MetabindContent.DateTime { __data["createdAt"] }
        public var updatedAt: MetabindContent.DateTime { __data["updatedAt"] }
        public var lastPublishedVersion: Int? { __data["lastPublishedVersion"] }
        public var resolvedRef: ResolvedRef { __data["resolvedRef"] }

        public struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

          public var contentFields: ContentFields { _toFragment() }
        }

        public typealias ResolvedRef = ContentFields.ResolvedRef
      }

      /// ContentUpdated.ResolvedRef
      ///
      /// Parent Type: `ResolvedPackageRef`
      public struct ResolvedRef: MetabindContent.SelectionSet {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public static var __parentType: any ApolloAPI.ParentType { MetabindContent.Objects.ResolvedPackageRef }
        public static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .fragment(ResolvedPackageRefFields.self),
        ] }
        public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          ContentUpdatedSubscription.Data.ContentUpdated.ResolvedRef.self,
          ResolvedPackageRefFields.self
        ] }

        public var package: MetabindContent.ID { __data["package"] }
        public var dependencies: [MetabindContent.ID] { __data["dependencies"] }

        public struct Fragments: FragmentContainer {
          public let __data: DataDict
          public init(_dataDict: DataDict) { __data = _dataDict }

          public var resolvedPackageRefFields: ResolvedPackageRefFields { _toFragment() }
        }
      }
    }
  }
}
