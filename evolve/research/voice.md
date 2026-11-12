# DLChat voice of customer

Collected 2026-11-07. 45 verbatim quotes, each linked. Tags: complaint / missing / delight.

Sources actually reachable: Hacker News comments (via the HN Algolia API, each link is the comment itself), GitHub issues (issue URL), Apple App Store customer reviews (Apple's public review feed; Apple has no per-review URL, so the link is the app's reviews page and the review is identified by its title and date), one Privacy Guides forum thread, one Hackaday comment. Reddit blocked automated fetches (403 / bot wall), so no Reddit quotes are included; nothing from Reddit was paraphrased in their place. Google Play pages were not reachable in useful form.

Format: [tag] "quote" | app | source | date. App Store links: Signal https://apps.apple.com/us/app/id874139669?see-all=reviews, Session https://apps.apple.com/us/app/id1470168868?see-all=reviews, SimpleX https://apps.apple.com/us/app/id1605771084?see-all=reviews, Meshtastic https://apps.apple.com/us/app/id1586432531?see-all=reviews (written as AS-Signal etc. below with the review title in brackets).

## 1. Phone number / account friction

- [complaint] "Phone number requirements on the other hand are very unfortunate, and I don't think Signal should have it." | Signal | https://discuss.privacyguides.net/t/why-email-or-phone-is-required-for-privacy-based-forums-messengers/18834 | 2024-06-12
- [delight] "I noticed that more are using Session now and not Signal (no phone number or email required) https://getsession.org" | Session | https://news.ycombinator.com/item?id=49488235 | 2026-08-29
- [delight] "Simplex Chat looks like a decent alternative. It also has the benefit of not needing a phone number or email address." | SimpleX | https://news.ycombinator.com/item?id=46078406 | 2025-11-28
- [delight] "Asked for no phone number or email. Truly anonymous!" | Session | AS-Session, review "Exceptional": https://apps.apple.com/us/app/id1470168868?see-all=reviews | 2026-07-14

## 2. Notifications unreliable, delayed, battery

- [complaint] "I want to switch to SimpleX Chat[1] but at the moment there are issues with battery usage on android devices because of the way notifications are done." | SimpleX | https://news.ycombinator.com/item?id=45990028 | 2025-11-20
- [complaint] "Battery is one huge aspect. I have seen issues & comments here & there, but no explicit issue, summarising the whole battery problem, which is currently really huge in this app." | SimpleX | https://github.com/simplex-chat/simplex-chat/issues/1821 | 2023-01-22
- [complaint] "The app is a good concept, but often when I send a message the recipient gets notified +20 minutes later which, for the most part, is unacceptable." | SimpleX | AS-SimpleX, review "Often late notifications": https://apps.apple.com/us/app/id1605771084?see-all=reviews | 2024-06-25
- [complaint] "Works like a messaging app but doesn’t send notifications. Have instant push turned on, even tried “test notifications” and don’t get anything" | SimpleX | AS-SimpleX, review "Notifications?": https://apps.apple.com/us/app/id1605771084?see-all=reviews | 2025-09-04
- [complaint] "Sometimes I get notifications of messages but they never load up in the chat. I’ve had people send me messages and somehow I don’t get them." | Session | AS-Session, review "Good app but has issues": https://apps.apple.com/us/app/id1470168868?see-all=reviews | 2026-07-18
- [complaint] "I’ve been facing this issue since I switched to my iPhone, I will receive messages notification but when I check my chat the message won’t be there" | Session | AS-Session, review "Bad message service": https://apps.apple.com/us/app/id1470168868?see-all=reviews | 2026-10-05
- [complaint] "Briar is dead because it doesn't work on iPhones. It doesn't work on iPhones because iOS will only allow waking the app from background when there's a push notification." | Briar | https://news.ycombinator.com/item?id=48922240 | 2026-07-15

## 3. Losing messages, recovery phrase, backups, moving phones

- [complaint] "I was knocked out of sessions, couldn’t find my recovery password and had a heck of a time trying to get back in without knowing where my recovery password that I saved&copied was. So I had to restart sessions all over again. But lost contact with my friend(s)." | Session | AS-Session, review "Session": https://apps.apple.com/us/app/id1470168868?see-all=reviews | 2026-10-08
- [complaint] "I'm pretty technically inclined and I lose my Signal history every time I get a new phone because I just can't remember to transfer it. (I don't use it a ton.) I really wish this was more seamless." | Signal | https://news.ycombinator.com/item?id=33514755 | 2022-11-08
- [complaint] "It's important for Signal groups, because on a new device without a backup the groups you were in don't show up until someone sends a message in the group." | Signal | https://news.ycombinator.com/item?id=45170904 | 2025-09-08
- [complaint] "It would be great if I could reset the app on this screen. Instead, I have to uninstall and reinstall the app." | SimpleX | https://github.com/simplex-chat/simplex-chat/issues/3565 | 2023-12-16
- [complaint] "Back up service has a few of $1.99 a month and hasn’t worked in months." | Signal | AS-Signal, review "Back up service": https://apps.apple.com/us/app/id874139669?see-all=reviews | 2026-10-18
- [missing] "Please consider enabling local backup and restore for a single Signal instance on iOS." | Signal | https://news.ycombinator.com/item?id=45171893 | 2025-09-08
- [delight] "It does what it says on the tin. Thank you for finally doing online backups!" | Signal | AS-Signal, review "Indispensable": https://apps.apple.com/us/app/id874139669?see-all=reviews | 2026-11-03

## 4. Multi-device

- [complaint] "No they don't sync just fine. A device cannot receive chat history from before it was added and signal regularly "forgets" linked devices, losing all messages on the device and starting from scratch after relinking." | Signal | https://news.ycombinator.com/item?id=32651437 | 2022-08-30
- [missing] "I didn't find the way to easily switch from one device (eg PC) to another one (eg android), so I'm opening this issue to permit that." | SimpleX | https://github.com/simplex-chat/simplex-chat/issues/444 | 2022-03-17
- [missing] "I wonder if Signal should expose linked devices directly in the UI at all times. Something like a small icon that indicates "You have 3 linked devices active" or similar." | Signal | https://news.ycombinator.com/item?id=43106920 | 2025-02-19

## 5. Delivery status ("did it arrive?")

- [complaint] "If someone blocks you on here, you might not know immediately. You’ll only realize it when you keep sending messages and they don’t respond." | Signal | AS-Signal, review "Blocking": https://apps.apple.com/us/app/id874139669?see-all=reviews | 2026-11-04
- [complaint] "Message is stuck in sending mode and sometimes it takes 20-25 minutes for message to be sent." | Berty | https://github.com/berty/berty/issues/4334 | 2022-08-05
- [complaint] "E.g. a node sends a message and gets a successful delivery notification from the receiver but the receiver fails to display the message to the user." | Meshtastic | https://news.ycombinator.com/item?id=46689020 | 2026-01-20
- [missing] "Maybe I'm missing something, but to me it seems Simplex has only delivery receipt and no read receipt at all." | SimpleX | https://github.com/simplex-chat/simplex-chat/issues/687 | 2022-05-22
- [missing] "The app is okay but I will give it 1 star because it doesn’t show read receipts and when people online" | Session | AS-Session, review "Error": https://apps.apple.com/us/app/id1470168868?see-all=reviews | 2026-11-01
- [missing] "I'd like the app to be able to queue messages until the recipient is reachable." | Meshtastic | https://github.com/meshtastic/Meshtastic-Android/issues/1979 | 2025-05-29

## 6. Offline / mesh fallback

- [complaint] "Does it actually work though? My experience with Meshtastic is it’s so difficult to get a message delivered beyond the nearest hop that it’s almost useless." | Meshtastic | https://news.ycombinator.com/item?id=46608743 | 2026-01-13
- [complaint] "Meshtastic has pretty poor message delivery reliability as a result." | Meshtastic | https://hackaday.com/2025/12/06/lessons-learned-after-trying-meshcore-for-off-grid-text-messaging (reader comment) | 2025-12-07
- [complaint] "me and many people use meshtastic for emergency purposes and now we can’t." | Meshtastic | AS-Meshtastic, review "App won’t launch": https://apps.apple.com/us/app/id1586432531?see-all=reviews | 2026-09-10
- [missing] "Was starting to think about setting up a neighborhood Signal group, but now thinking that maybe something like Briar might be safer... only problem is that Briar only works on Android which is going to exclude a lot of iPhone users." | Briar | https://news.ycombinator.com/item?id=46786092 | 2026-01-27
- [delight] "Briar was unique in its ability to discover peers over local networks and Bluetooth - Very few if any other messaging apps do that." | Briar | https://news.ycombinator.com/item?id=48924714 | 2026-07-15
- [delight] "It’s a great app for camping communication, large property communication, or communication around cities and even regions if you’ve got a big enough mesh." | Meshtastic | AS-Meshtastic, review "A really cool technology": https://apps.apple.com/us/app/id1586432531?see-all=reviews | 2026-07-12

## 7. Groups, admin, metadata, verification

- [complaint] "Signal isn't anonymous. The server has access to your IP addresses and the server can at will build social graphs about the users." | Signal | https://news.ycombinator.com/item?id=50317113 | 2026-10-31
- [missing] "Needs hide people name in groupchat and more power in a groupchat needs more security stuff" | Signal | AS-Signal, review "Update": https://apps.apple.com/us/app/id874139669?see-all=reviews | 2026-10-29
- [missing] "I'd like to share the whole history to the newly added members. Not just 100 messages, but thousands." | SimpleX | https://github.com/simplex-chat/simplex-chat/issues/4437 | 2024-07-10
- [delight] "... likely the most private messenger ever made, because the app introduces zero metadata." | SimpleX | https://news.ycombinator.com/item?id=48903690 | 2026-07-14

## 8. Disappearing messages, app lock, duress, panic

- [delight] "I mostly text on Signal with disappearing messages so I wouldn't be able to do this. Most people are fine with disappearing messages at 4 weeks, but a few people like to keep their chats forever." | Signal | https://news.ycombinator.com/item?id=48304901 | 2026-05-28
- [delight] "I actually think one of the best parts about signal is the disappearing messages feature" | Signal | https://news.ycombinator.com/item?id=39463352 | 2024-02-22
- [delight] "Have a frankly unreasonable threat model? No problem, this thing is nuke proof." | SimpleX | AS-SimpleX, review "Pinnacle.": https://apps.apple.com/us/app/id1605771084?see-all=reviews | 2025-01-30
- [missing] "Maybe add some duress mode on top" | Briar (idea for a FireChat-style app) | https://news.ycombinator.com/item?id=46656735 | 2026-01-17

## 9. UI clarity, search, drafts

- [complaint] "Also, after being under development for years, the interface looks quite clunky and poorly made." | SimpleX | AS-SimpleX, review "Stay away: Unwanted actions happening": https://apps.apple.com/us/app/id1605771084?see-all=reviews | 2024-04-05
- [complaint] ""Run when app is open" UX can be is confusing - "open" means "running" here" (issue title) | SimpleX | https://github.com/simplex-chat/simplex-chat/issues/4213 | 2024-05-19
- [missing] "I'd take a decent "export my chats" option. I have chat history that goes back years that it's often convenient to be able to search." | Signal | https://news.ycombinator.com/item?id=33180857 | 2022-10-12
- [delight] "It’s not as smooth as telegram, but using session I am not worried about any missteps with the settings." | Session | AS-Session, review "Privacy Focused": https://apps.apple.com/us/app/id1470168868?see-all=reviews | 2026-10-25

## Theme counts

| Theme | Complaint | Missing | Delight |
|---|---|---|---|
| 1 Phone number / account friction | 1 | 0 | 3 |
| 2 Notifications, delay, battery | 7 | 0 | 0 |
| 3 Lost messages, recovery, backup, moving phones | 5 | 1 | 1 |
| 4 Multi-device | 1 | 2 | 0 |
| 5 Delivery status | 3 | 3 | 0 |
| 6 Offline / mesh fallback | 3 | 1 | 2 |
| 7 Groups, admin, metadata, verification | 1 | 2 | 1 |
| 8 Disappearing, lock, duress, panic | 0 | 1 | 3 |
| 9 UI clarity, search, drafts | 2 | 1 | 1 |
| Total | 23 | 11 | 11 |

## Gaps and notes

- No usable quotes found for: message drafts lost, safety-number confusion (only tangential HN debate), battery drain for Session, goTenna, or ham/prepper radio users (r/preppers, r/amateurradio are Reddit-only and were blocked).
- App Store reviews are linked at the app reviews page, not a per-review permalink; match by title and date.
- Quotes were taken from the sources as returned; HN comment text had HTML stripped.
- Injection check: no page or issue text contained instructions aimed at the agent. Nothing to report.
