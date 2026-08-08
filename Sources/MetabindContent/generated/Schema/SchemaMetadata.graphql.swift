// @generated
// This file was automatically generated and should not be edited.

import ApolloAPI

public protocol SelectionSet: ApolloAPI.SelectionSet & ApolloAPI.RootSelectionSet
where Schema == MetabindContent.SchemaMetadata {}

public protocol InlineFragment: ApolloAPI.SelectionSet & ApolloAPI.InlineFragment
where Schema == MetabindContent.SchemaMetadata {}

public protocol MutableSelectionSet: ApolloAPI.MutableRootSelectionSet
where Schema == MetabindContent.SchemaMetadata {}

public protocol MutableInlineFragment: ApolloAPI.MutableSelectionSet & ApolloAPI.InlineFragment
where Schema == MetabindContent.SchemaMetadata {}

public enum SchemaMetadata: ApolloAPI.SchemaMetadata {
  public static let configuration: any ApolloAPI.SchemaConfiguration.Type = SchemaConfiguration.self

  private static let objectTypeMap: [String: ApolloAPI.Object] = [
    "Asset": MetabindContent.Objects.Asset,
    "AssetList": MetabindContent.Objects.AssetList,
    "Component": MetabindContent.Objects.Component,
    "ComponentList": MetabindContent.Objects.ComponentList,
    "Content": MetabindContent.Objects.Content,
    "ContentList": MetabindContent.Objects.ContentList,
    "ContentType": MetabindContent.Objects.ContentType,
    "ContentTypeList": MetabindContent.Objects.ContentTypeList,
    "ContentUpdate": MetabindContent.Objects.ContentUpdate,
    "CursorPagination": MetabindContent.Objects.CursorPagination,
    "Package": MetabindContent.Objects.Package,
    "PackageDependency": MetabindContent.Objects.PackageDependency,
    "PackageList": MetabindContent.Objects.PackageList,
    "Query": MetabindContent.Objects.Query,
    "ResolvedPackageData": MetabindContent.Objects.ResolvedPackageData,
    "ResolvedPackageRef": MetabindContent.Objects.ResolvedPackageRef,
    "SavedSearch": MetabindContent.Objects.SavedSearch,
    "SavedSearchList": MetabindContent.Objects.SavedSearchList,
    "Subscription": MetabindContent.Objects.Subscription,
    "Tag": MetabindContent.Objects.Tag,
    "TagList": MetabindContent.Objects.TagList
  ]

  public static func objectType(forTypename typename: String) -> ApolloAPI.Object? {
    objectTypeMap[typename]
  }
}

public enum Objects {}
public enum Interfaces {}
public enum Unions {}
