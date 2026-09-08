export default defineComponent({
  metadata: { title: "SpotlightInfoRail" },
  properties: {
    title: PropertyString({ defaultValue: "Thoughtful by design" }),
    firstTitle: PropertyString({ defaultValue: "Natural textures" }),
    firstDetail: PropertyString({ defaultValue: "Layer soft fabrics and warm wood tones." }),
    secondTitle: PropertyString({ defaultValue: "Everyday comfort" }),
    secondDetail: PropertyString({ defaultValue: "Make space to slow down and settle in." }),
    thirdTitle: PropertyString({ defaultValue: "Your own style" }),
    thirdDetail: PropertyString({ defaultValue: "Mix favorite pieces into a home that feels personal." }),
  },
  body: (props) => {
    const cards = [
      { icon: "leaf.fill", title: props.firstTitle, detail: props.firstDetail },
      { icon: "sun.max.fill", title: props.secondTitle, detail: props.secondDetail },
      { icon: "heart.fill", title: props.thirdTitle, detail: props.thirdDetail },
    ];
    return VStack({ spacing: 16, alignment: "leading" }, [
      Text(props.title).font("title2").fontWeight("bold").padding("horizontal", 16),
      ScrollView({ axis: "horizontal", showsIndicators: false }, [
        HStack({ spacing: 12, alignment: "top" }, [ForEach(cards, card =>
          VStack({ spacing: 12, alignment: "leading" }, [
            Image({ systemName: card.icon }).font("title2").foregroundStyle(Color("#526149")),
            Text(card.title).font("headline"),
            Text(card.detail).font("body").foregroundStyle(Color("secondary")),
          ])
            .frame({ width: 210, alignment: "leading" })
            .padding(20)
            .background(Color("secondarySystemBackground"))
            .cornerRadius(20)
        )]).padding("horizontal", 16),
      ]),
    ]);
  },
  previews: [
    Self({}).previewName("Default"),
    Self({ firstTitle: "Details that make the room feel complete", firstDetail: "A longer description to check wrapping on a narrow phone display." }).previewName("Long card"),
  ],
});
