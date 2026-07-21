// @generated
// This file was automatically generated and should not be edited.

import ApolloAPI

public struct AssetFilter: InputObject {
  public private(set) var __data: InputDict

  public init(_ data: InputDict) {
    __data = data
  }

  public init(
    name: GraphQLNullable<FilterOperators> = nil,
    type: GraphQLNullable<FilterOperators> = nil,
    tags: GraphQLNullable<FilterOperators> = nil,
    size: GraphQLNullable<NumberFilterOperators> = nil,
    width: GraphQLNullable<NumberFilterOperators> = nil,
    height: GraphQLNullable<NumberFilterOperators> = nil
  ) {
    __data = InputDict([
      "name": name,
      "type": type,
      "tags": tags,
      "size": size,
      "width": width,
      "height": height
    ])
  }

  public var name: GraphQLNullable<FilterOperators> {
    get { __data["name"] }
    set { __data["name"] = newValue }
  }

  public var type: GraphQLNullable<FilterOperators> {
    get { __data["type"] }
    set { __data["type"] = newValue }
  }

  public var tags: GraphQLNullable<FilterOperators> {
    get { __data["tags"] }
    set { __data["tags"] = newValue }
  }

  public var size: GraphQLNullable<NumberFilterOperators> {
    get { __data["size"] }
    set { __data["size"] = newValue }
  }

  public var width: GraphQLNullable<NumberFilterOperators> {
    get { __data["width"] }
    set { __data["width"] = newValue }
  }

  public var height: GraphQLNullable<NumberFilterOperators> {
    get { __data["height"] }
    set { __data["height"] = newValue }
  }
}
