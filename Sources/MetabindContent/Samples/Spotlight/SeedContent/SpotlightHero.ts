export default defineComponent({
  metadata: { title: "SpotlightHero" },
  properties: {
    eyebrow: PropertyString({ defaultValue: "OAK & IVORY" }),
    title: PropertyString({ defaultValue: "Make room for everyday moments" }),
    subtitle: PropertyString({ defaultValue: "Warm textures, thoughtful details, and a space that feels like you." }),
  },
  body: (props) => VStack({ spacing: 16, alignment: "leading" }, [
    Image({ systemName: "sofa.fill" }).font(52).foregroundStyle(Color("#526149")),
    Text(props.eyebrow).font("caption").fontWeight("semibold"),
    Text(props.title).font("largeTitle").fontWeight("bold"),
    Text(props.subtitle).font("body"),
  ])
    .frame({ maxWidth: Infinity, alignment: "leading" })
    .padding(24)
    .foregroundStyle(Color("#292E25"))
    .background(Color("#EDE8DB"))
    .cornerRadius(24)
    .padding("horizontal", 16),
  previews: [
    Self({}).previewName("Default"),
    Self({ title: "A calmer corner for every part of your day", subtitle: "Find inspiration for gathering, unwinding, and everything in between." }).previewName("Long copy"),
  ],
});
