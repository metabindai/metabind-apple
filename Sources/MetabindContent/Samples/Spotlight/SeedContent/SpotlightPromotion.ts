export default defineComponent({
  metadata: { title: "SpotlightPromotion" },
  properties: {
    title: PropertyString({ defaultValue: "A fresh perspective for your space" }),
    message: PropertyString({ defaultValue: "Discover warm colors and inviting details in our seasonal collection." }),
    buttonTitle: PropertyString({ defaultValue: "Explore the collection" }),
    actionURL: PropertyString({ defaultValue: "railpromotion://cta/seasonal-collection" }),
  },
  body: (props) => {
    const environment = useEnvironment();
    return VStack({ spacing: 24, alignment: "leading" }, [
      Image({ systemName: "sparkles" }).font(48).foregroundStyle(Color("#526149")),
      Text("OAK & IVORY").font("caption").fontWeight("semibold"),
      Text(props.title).font("largeTitle").fontWeight("bold"),
      Text(props.message).font("body"),
      Button({
        action: () => environment.openURL(props.actionURL),
        label: Text(props.buttonTitle)
          .font("headline")
          .frame({ maxWidth: Infinity })
          .padding(18)
          .foregroundStyle(Color("white"))
          .background(Color("#526149"))
          .cornerRadius(16),
      }),
      Text("Sample promotion — no purchase or discount is applied.")
        .font("caption").foregroundStyle(Color("secondary")),
    ])
      .frame({ maxWidth: Infinity, alignment: "leading" })
      .padding(24);
  },
  previews: [
    Self({}).previewName("Default"),
    Self({ title: "Simple changes, a whole new feeling", buttonTitle: "See the seasonal collection" }).previewName("Alternate campaign"),
  ],
});
