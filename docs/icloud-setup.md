# iCloud push setup (owner steps, about 10 minutes)

Done already through the App Store Connect API (2026-11-07): Push Notifications and iCloud enabled on
the app ID com.harrisonfischberg.dlchat (H2WG93K4PD).

1. **Create the iCloud container.** developer.apple.com > Certificates, Identifiers & Profiles >
   Identifiers > the "+" button > iCloud Containers > Continue. Description: DLChat. Identifier:
   `iCloud.com.harrisonfischberg.dlchat` > Register.
2. **Attach it to the app.** Identifiers > com.harrisonfischberg.dlchat > iCloud > Edit (or Configure) >
   tick `iCloud.com.harrisonfischberg.dlchat` > Continue > Save.
3. **Let Xcode refresh signing once.** Open Xcode, Settings > Accounts, make sure your Apple ID is signed in.
   Then: `open ~/projects/dlchat/DLChat.xcodeproj`, select the DLChat target > Signing & Capabilities.
   Tell me when it shows no red errors (I add the entitlements file first, so the iCloud and Push
   sections appear).
4. **Publish the database layout.** icloud.developer.apple.com > CloudKit Console > the DLChat
   container > Schema: record type `DLFrame` with fields `mailbox` (String, Queryable),
   `event` (Bytes), `expires` (Date/Time); add a Queryable index on `createdTimestamp`
   (creationDate). Then "Deploy Schema Changes" to Production. (I can create it in the Development
   environment by running the app once from Xcode, so this is mostly clicking Deploy.)

After step 4 I flip `CloudCarrier.isConfigured`, add the entitlements and background push mode, test on
your phone, and upload a build.
