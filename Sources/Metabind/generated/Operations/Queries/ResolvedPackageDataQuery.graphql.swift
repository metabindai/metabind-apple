// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

public class ResolvedPackageDataQuery: GraphQLQuery {
  public static let operationName: String = "ResolvedPackageDataQuery"
  public static let operationDocument: ApolloAPI.OperationDocument = .init(
    definition: .init(
      #"query ResolvedPackageDataQuery($packageId: ID!) { resolvedPackageData(packageId: $packageId) { __typename ...ResolvedPackageDataFields } }"#,
      fragments: [ResolvedPackageDataFields.self]
    ))

  public var packageId: ID

  public init(packageId: ID) {
    self.packageId = packageId
  }

  public var __variables: Variables? { ["packageId": packageId] }

  public struct Data: Metabind.SelectionSet {
    public let __data: DataDict
    public init(_dataDict: DataDict) { __data = _dataDict }

    public static var __parentType: any ApolloAPI.ParentType { Metabind.Objects.Query }
    public static var __selections: [ApolloAPI.Selection] { [
      .field("resolvedPackageData", ResolvedPackageData?.self, arguments: ["packageId": .variable("packageId")]),
    ] }

    public var resolvedPackageData: ResolvedPackageData? { __data["resolvedPackageData"] }

    /// ResolvedPackageData
    ///
    /// Parent Type: `ResolvedPackageData`
    public struct ResolvedPackageData: Metabind.SelectionSet {
      public let __data: DataDict
      public init(_dataDict: DataDict) { __data = _dataDict }

      public static var __parentType: any ApolloAPI.ParentType { Metabind.Objects.ResolvedPackageData }
      public static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
        .fragment(ResolvedPackageDataFields.self),
      ] }

      public var id: Metabind.ID { __data["id"] }
      public var version: String { __data["version"] }
      public var components: String { __data["components"] }
      public var assets: String { __data["assets"] }

      public struct Fragments: FragmentContainer {
        public let __data: DataDict
        public init(_dataDict: DataDict) { __data = _dataDict }

        public var resolvedPackageDataFields: ResolvedPackageDataFields { _toFragment() }
      }
    }
  }
}
