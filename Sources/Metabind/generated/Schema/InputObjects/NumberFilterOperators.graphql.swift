// @generated
// This file was automatically generated and should not be edited.

import ApolloAPI

public struct NumberFilterOperators: InputObject {
  public private(set) var __data: InputDict

  public init(_ data: InputDict) {
    __data = data
  }

  public init(
    eq: GraphQLNullable<Double> = nil,
    ne: GraphQLNullable<Double> = nil,
    gt: GraphQLNullable<Double> = nil,
    gte: GraphQLNullable<Double> = nil,
    lt: GraphQLNullable<Double> = nil,
    lte: GraphQLNullable<Double> = nil,
    `in`: GraphQLNullable<[Double]> = nil,
    nin: GraphQLNullable<[Double]> = nil
  ) {
    __data = InputDict([
      "eq": eq,
      "ne": ne,
      "gt": gt,
      "gte": gte,
      "lt": lt,
      "lte": lte,
      "in": `in`,
      "nin": nin
    ])
  }

  public var eq: GraphQLNullable<Double> {
    get { __data["eq"] }
    set { __data["eq"] = newValue }
  }

  public var ne: GraphQLNullable<Double> {
    get { __data["ne"] }
    set { __data["ne"] = newValue }
  }

  public var gt: GraphQLNullable<Double> {
    get { __data["gt"] }
    set { __data["gt"] = newValue }
  }

  public var gte: GraphQLNullable<Double> {
    get { __data["gte"] }
    set { __data["gte"] = newValue }
  }

  public var lt: GraphQLNullable<Double> {
    get { __data["lt"] }
    set { __data["lt"] = newValue }
  }

  public var lte: GraphQLNullable<Double> {
    get { __data["lte"] }
    set { __data["lte"] = newValue }
  }

  public var `in`: GraphQLNullable<[Double]> {
    get { __data["in"] }
    set { __data["in"] = newValue }
  }

  public var nin: GraphQLNullable<[Double]> {
    get { __data["nin"] }
    set { __data["nin"] = newValue }
  }
}
