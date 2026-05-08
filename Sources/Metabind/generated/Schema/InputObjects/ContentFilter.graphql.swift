// @generated
// This file was automatically generated and should not be edited.

import ApolloAPI

public struct ContentFilter: InputObject {
  public private(set) var __data: InputDict

  public init(_ data: InputDict) {
    __data = data
  }

  public init(
    name: GraphQLNullable<FilterOperators> = nil,
    description: GraphQLNullable<FilterOperators> = nil,
    tags: GraphQLNullable<FilterOperators> = nil,
    typeId: GraphQLNullable<FilterOperators> = nil,
    locale: GraphQLNullable<FilterOperators> = nil,
    createdAt: GraphQLNullable<DateFilterOperators> = nil,
    updatedAt: GraphQLNullable<DateFilterOperators> = nil
  ) {
    __data = InputDict([
      "name": name,
      "description": description,
      "tags": tags,
      "typeId": typeId,
      "locale": locale,
      "createdAt": createdAt,
      "updatedAt": updatedAt
    ])
  }

  public var name: GraphQLNullable<FilterOperators> {
    get { __data["name"] }
    set { __data["name"] = newValue }
  }

  public var description: GraphQLNullable<FilterOperators> {
    get { __data["description"] }
    set { __data["description"] = newValue }
  }

  public var tags: GraphQLNullable<FilterOperators> {
    get { __data["tags"] }
    set { __data["tags"] = newValue }
  }

  public var typeId: GraphQLNullable<FilterOperators> {
    get { __data["typeId"] }
    set { __data["typeId"] = newValue }
  }

  public var locale: GraphQLNullable<FilterOperators> {
    get { __data["locale"] }
    set { __data["locale"] = newValue }
  }

  public var createdAt: GraphQLNullable<DateFilterOperators> {
    get { __data["createdAt"] }
    set { __data["createdAt"] = newValue }
  }

  public var updatedAt: GraphQLNullable<DateFilterOperators> {
    get { __data["updatedAt"] }
    set { __data["updatedAt"] = newValue }
  }
}
