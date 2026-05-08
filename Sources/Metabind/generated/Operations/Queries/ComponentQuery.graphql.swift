// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

public class ComponentQuery: GraphQLQuery {
  public static let operationName: String = "ComponentQuery"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    definition: .init(
      #"query ComponentQuery($id: ID!) { component(id: $id) { __typename ...ComponentFields } }"#,
      fragments: [ComponentFields.self]
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
      .field("component", Component?.self, arguments: ["id": .variable("id")]),
    ] }

    public var component: Component? { __data["component"] }

    /// Component
    ///
    /// Parent Type: `Component`
    public struct Component: Metabind.SelectionSet {
      public let __data: DataDict
      public init(_dataDict: DataDict) { __data = _dataDict }

      public static var __parentType: any ApolloAPI.ParentType { Metabind.Objects.Component }
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .fragment(ComponentFields.self),
      ] }

      public var id: Metabind.ID { __data["id"] }
      public var name: String { __data["name"] }
      public var compiled: String { __data["compiled"] }
      public var updatedAt: Metabind.DateTime { __data["updatedAt"] }

      public struct Fragments: FragmentContainer {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public var componentFields: ComponentFields { _toFragment() }
      }
    }
  }
}
