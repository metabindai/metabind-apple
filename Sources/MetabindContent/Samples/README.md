# MetabindContent samples

Two sample apps that exercise the `MetabindContent` library. They live beside
the code they demonstrate, but they are not part of the package: the target's
`exclude` list in `Package.swift` keeps this directory out of the build, the
same way it keeps out `GraphQL/`. If you add folders here, extend that list.

| Sample | Shows |
|---|---|
| [Retail](Retail) | A minimal `MetabindContent` integration: initialize the client, render content, and route between pages. |
| [Spotlight](Spotlight) | A richer `MetabindContent` integration: multiple content blocks, real-time updates, push notifications, and deep links. Includes a full account-setup guide. |

Each project references this package by local path, so building a sample
compiles the SDK from your current checkout — the fastest way to see a source
change running in a real app. Open the sample's `.xcodeproj` and fill in the
`<#placeholder#>` configuration values (API key, organization, project, and
content IDs) in the app file; each sample's README covers account setup.

To use a sample outside this repository, change its package reference from the
local path to `https://github.com/metabindai/metabind-apple`.
