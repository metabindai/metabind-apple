// @generated
// This file was automatically generated and should not be edited.

import ApolloAPI

public struct DateFilterOperators: InputObject {
  public private(set) var __data: InputDict

  public init(_ data: InputDict) {
    __data = data
  }

  public init(
    eq: GraphQLNullable<DateTime> = nil,
    ne: GraphQLNullable<DateTime> = nil,
    gt: GraphQLNullable<DateTime> = nil,
    gte: GraphQLNullable<DateTime> = nil,
    lt: GraphQLNullable<DateTime> = nil,
    lte: GraphQLNullable<DateTime> = nil
  ) {
    __data = InputDict([
      "eq": eq,
      "ne": ne,
      "gt": gt,
      "gte": gte,
      "lt": lt,
      "lte": lte
    ])
  }

  public var eq: GraphQLNullable<DateTime> {
    get { __data["eq"] }
    set { __data["eq"] = newValue }
  }

  public var ne: GraphQLNullable<DateTime> {
    get { __data["ne"] }
    set { __data["ne"] = newValue }
  }

  public var gt: GraphQLNullable<DateTime> {
    get { __data["gt"] }
    set { __data["gt"] = newValue }
  }

  public var gte: GraphQLNullable<DateTime> {
    get { __data["gte"] }
    set { __data["gte"] = newValue }
  }

  public var lt: GraphQLNullable<DateTime> {
    get { __data["lt"] }
    set { __data["lt"] = newValue }
  }

  public var lte: GraphQLNullable<DateTime> {
    get { __data["lte"] }
    set { __data["lte"] = newValue }
  }
}
