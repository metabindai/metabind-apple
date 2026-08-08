// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

public struct PackageFields: MetabindContent.SelectionSet, Fragment {
  public static var fragmentDefinition: StaticString {
    #"fragment PackageFields on Package { __typename id version components { __typename ...ComponentFields } assets { __typename ...AssetFields } dependencies { __typename ...PackageDependencyFields } compiled resolvedRef { __typename ...ResolvedPackageRefFields } }"#
  }

  public let __data: DataDict
  public init(_dataDict: DataDict) { __data = _dataDict }

  public static var __parentType: any ApolloAPI.ParentType { MetabindContent.Objects.Package }
  public static var __selections: [ApolloAPI.Selection] { [
    .field("__typename", String.self),
    .field("id", MetabindContent.ID.self),
    .field("version", String.self),
    .field("components", [Component].self),
    .field("assets", [Asset].self),
    .field("dependencies", [Dependency].self),
    .field("compiled", String.self),
    .field("resolvedRef", ResolvedRef.self),
  ] }
  public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
    PackageFields.self
  ] }

  public var id: MetabindContent.ID { __data["id"] }
  public var version: String { __data["version"] }
  public var components: [Component] { __data["components"] }
  public var assets: [Asset] { __data["assets"] }
  public var dependencies: [Dependency] { __data["dependencies"] }
  public var compiled: String { __data["compiled"] }
  public var resolvedRef: ResolvedRef { __data["resolvedRef"] }

  /// Component
  ///
  /// Parent Type: `Component`
  public struct Component: MetabindContent.SelectionSet {
    public let __data: DataDict
    public init(_dataDict: DataDict) { __data = _dataDict }

    public static var __parentType: any ApolloAPI.ParentType { MetabindContent.Objects.Component }
    public static var __selections: [ApolloAPI.Selection] { [
      .field("__typename", String.self),
      .fragment(ComponentFields.self),
    ] }
    public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      PackageFields.Component.self,
      ComponentFields.self
    ] }

    public var id: MetabindContent.ID { __data["id"] }
    public var name: String { __data["name"] }
    public var compiled: String { __data["compiled"] }
    public var updatedAt: MetabindContent.DateTime { __data["updatedAt"] }

    public struct Fragments: FragmentContainer {
      public let __data: DataDict
      public init(_dataDict: DataDict) { __data = _dataDict }

      public var componentFields: ComponentFields { _toFragment() }
    }
  }

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
      PackageFields.Asset.self,
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

  /// Dependency
  ///
  /// Parent Type: `PackageDependency`
  public struct Dependency: MetabindContent.SelectionSet {
    public let __data: DataDict
    public init(_dataDict: DataDict) { __data = _dataDict }

    public static var __parentType: any ApolloAPI.ParentType { MetabindContent.Objects.PackageDependency }
    public static var __selections: [ApolloAPI.Selection] { [
      .field("__typename", String.self),
      .fragment(PackageDependencyFields.self),
    ] }
    public static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
      PackageFields.Dependency.self,
      PackageDependencyFields.self
    ] }

    public var projectId: MetabindContent.ID { __data["projectId"] }
    public var version: String { __data["version"] }

    public struct Fragments: FragmentContainer {
      public let __data: DataDict
      public init(_dataDict: DataDict) { __data = _dataDict }

      public var packageDependencyFields: PackageDependencyFields { _toFragment() }
    }
  }

  /// ResolvedRef
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
      PackageFields.ResolvedRef.self,
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
