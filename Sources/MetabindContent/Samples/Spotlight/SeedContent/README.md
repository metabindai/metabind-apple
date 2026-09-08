# Spotlight replacement content

These are new sample fixtures, not recovered copies of the original content.
They use native symbols and colors without uploading assets or calling external APIs.

| Block | Component source | Content values | Local setting |
| --- | --- | --- | --- |
| Hero | `SpotlightHero.ts` | `hero.json` | `SPOTLIGHT_SAMPLE_HERO_CONTENT_ID` |
| Information rail | `SpotlightInfoRail.ts` | `info-rail.json` | `SPOTLIGHT_SAMPLE_INFO_CONTENT_ID` |
| Promotion sheet | `SpotlightPromotion.ts` | `promotion.json` | `SPOTLIGHT_SAMPLE_PROMOTION_CONTENT_ID` |

The hero introduces “Make room for everyday moments.” The horizontal rail
contains three cards about texture, comfort, and personal style. The promotion
button opens `railpromotion://cta/seasonal-collection`; Spotlight intercepts
that URL, dismisses the sheet, and displays the selected CTA in the notification
demo. It does not navigate to a store or make a purchase.

## Validation

From this folder, using the Metabind CLI:

```sh
metabind validate component SpotlightHero.ts
metabind validate component SpotlightInfoRail.ts
metabind validate component SpotlightPromotion.ts
```

## Provisioning

Provisioning writes to the selected Metabind project. Inspect existing resources
first and use explicit organization and project IDs on every command.

For each row in the table:

1. Create its component with `metabind component create <source-file>`.
2. Create a view type with `metabind tool create --component <returned-component-id> --name <unique-name>`.
3. Create a content row with the returned type ID and the matching JSON values:

   ```sh
   metabind --org YOUR_ORG_ID --project YOUR_PROJECT_ID content create \
     --data '{"name":"Spotlight Hero","typeId":"RETURNED_TYPE_ID","description":"Spotlight sample hero"}' \
     --from-file hero.json
   ```

4. Read the resulting component, type, and content back before publishing.
5. Run `metabind publish` with a deliberate version bump after reviewing all
   pending project changes. This also publishes draft content rows. Read each new
   row back; if it still pins `draft`, use `metabind content retarget <id>
   --to-package <published-version>` to align and republish that row. Verify the
   resulting package version before testing the SDK.
6. Save the three returned content IDs and a restricted read key in the ignored
   `Config/Local.xcconfig`; build and run Spotlight on iPhone.

Do not replace or remove unrelated components already present in a project.

## Runtime checks

- Open **Home Screen**: the hero and information rail load; swipe the rail to the
  third card and scroll through the native product rows.
- Open **Push Notification**, schedule the local notification, and tap its banner:
  the promotion content appears in a sheet.
- Tap **Explore the collection**: the sheet closes and the selected CTA reads
  `seasonal-collection`.
- Test live updates separately with a deliberate, approved content edit and
  publication; the hero is the block configured for subscriptions.

Local structural validation and an Xcode build do not verify hosted rendering,
notification delivery, or the CTA. Those checks require provisioned content.
The SDK's API-key content endpoint returns published content, so draft-only rows
cannot be tested through the sample's normal connection.
