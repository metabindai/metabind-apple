// @generated
// This file was automatically generated and should not be edited.

import ApolloAPI

public struct FilterOperators: InputObject {
  public private(set) var __data: InputDict

  public init(_ data: InputDict) {
    __data = data
  }

  public init(
    eq: GraphQLNullable<String> = nil,
    ne: GraphQLNullable<String> = nil,
    `in`: GraphQLNullable<[String]> = nil,
    nin: GraphQLNullable<[String]> = nil,
    all: GraphQLNullable<[String]> = nil,
    any: GraphQLNullable<[String]> = nil,
    like: GraphQLNullable<String> = nil
  ) {
    __data = InputDict([
      "eq": eq,
      "ne": ne,
      "in": `in`,
      "nin": nin,
      "all": all,
      "any": any,
      "like": like
    ])
  }

  public var eq: GraphQLNullable<String> {
    get { __data["eq"] }
    set { __data["eq"] = newValue }
  }

  public var ne: GraphQLNullable<String> {
    get { __data["ne"] }
    set { __data["ne"] = newValue }
  }

  public var `in`: GraphQLNullable<[String]> {
    get { __data["in"] }
    set { __data["in"] = newValue }
  }

  public var nin: GraphQLNullable<[String]> {
    get { __data["nin"] }
    set { __data["nin"] = newValue }
  }

  public var all: GraphQLNullable<[String]> {
    get { __data["all"] }
    set { __data["all"] = newValue }
  }

  public var any: GraphQLNullable<[String]> {
    get { __data["any"] }
    set { __data["any"] = newValue }
  }

  public var like: GraphQLNullable<String> {
    get { __data["like"] }
    set { __data["like"] = newValue }
  }
}
