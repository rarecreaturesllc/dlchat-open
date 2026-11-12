#!/usr/bin/env python3 -I
"""Write Packages/DLCore/Sources/DLCore/Resources/dictionary.txt.

The text-coding dictionary: lowercase words, one per line, most common first.
Written by hand for this project (no third-party frequency list, so no
licence to carry; see docs/asset-licenses.md). Line order is the rank that
sets each word's Huffman weight, so it is part of the wire format: the file's
SHA-256 is pinned in TextCodecTests. Duplicates are dropped, first one wins.
"""
import re
import sys
from pathlib import Path

# Everyday texting words and contractions, ranked high so casual messages stay short
# (added 2026-11-07 after a 34-word "going to get food" message). Apostrophe-free
# spellings people actually type ("dont", "thats") are listed alongside.
CHAT = """
hey hi hello yeah yep nope nah thanks thank please sorry sure maybe really actually probably
i'm i'll i've i'd you're you'll you've we're we'll we've they're they'll it's that's
don't can't won't didn't isn't aren't wasn't doesn't haven't couldn't wouldn't shouldn't
let's there's what's where's who's here's how's y'all
im ill dont cant didnt isnt thats whats youre ive
gonna wanna gotta kinda lol omg idk btw
anything something nothing everything anybody anywhere somewhere everywhere
got take make made went come coming leaving left stay home house place store town car truck
call text talk tell ask think thought feel love miss hope wait stop start try put let use find
look bring buy give keep walk drive meet hang together interested about around over into
"""

WORDS = ("""
the i you to a and it is that in we of for on not have at be do they are can there this with but my me
what so he she will no all get was out up go if now one just your how here when need want know see
come back him her his them then who why where help yes ok okay like good time right say going been
""" + CHAT + """
had has did would could should must from by or as an our us their more some any too very again still
again today tonight tomorrow yesterday morning evening night noon afternoon day week hour minute
second now soon later before after until while since always never again once two three four five
six seven eight nine ten zero eleven twelve fifteen twenty thirty forty fifty sixty hundred thousand
first second last next other another same only also even much many few little big small long short
high low old new young ready done safe okay fine well bad wrong hurt sick dead alive hungry thirsty
tired cold hot warm dry wet dark light quiet loud fast slow close open shut locked clear empty full
people man woman men women child children kids baby family friend neighbor neighbors group team
everyone someone anyone nobody everybody somebody person guy guys boy girl mom dad wife husband
brother sister mother father son daughter grandma grandpa uncle aunt doctor nurse medic medical
police cop sheriff officer soldier guard guards driver pilot farmer farm farmers leader boss chief
captain sir mister
water food fuel gas gasoline diesel propane oil wood fire firewood stove heat heater battery
batteries power electric electricity generator solar radio phone cell signal antenna channel
frequency tower flashlight lantern candle candles matches lighter torch rope tape tarp tent blanket
blankets coat jacket boots shoes gloves hat mask clothes socks bag bags backpack box boxes bucket
can cans jar bottle bottles jug jugs tank barrel pump hose pipe pipes filter bleach soap
medicine medicines pills pill aspirin insulin antibiotics bandage bandages gauze splint wound
wounds bleeding blood broken fever pain injured injury infection sick ill unconscious breathing
heart stroke allergic allergy pregnant baby delivery labor oxygen supplies supply kit first aid
rice beans flour sugar salt coffee tea milk bread meat fish eggs corn potatoes canned dried
cooking cook eat eating drink drinking ration rations meal meals lunch dinner breakfast
gun guns rifle rifles pistol shotgun weapon weapons ammo ammunition bullets shells knife armed
shot shots shooting shoot fired gunfire explosion bomb threat danger dangerous enemy hostile
looters looting robbery attack attacked attacking raid intruder intruders trespassers stranger
strangers suspicious vehicle vehicles car cars truck trucks van bus jeep tractor trailer boat
bike bicycle motorcycle plane helicopter drone tank convoy
house home building barn shed garage cabin camp shelter basement cellar roof door doors window
windows gate gates fence wall bridge road roads street streets highway route trail path hill
mountain valley river creek lake pond well spring woods forest field fields farm church school
hospital clinic store shop market station depot warehouse office bank pharmacy town city county
village park lot yard corner crossroad intersection checkpoint roadblock blocked closed flooded
flood storm tornado hurricane earthquake wildfire smoke ash snow ice rain wind fog heat cold
north south east west northeast northwest southeast southwest left right up down near far inside
outside above below behind ahead between across along around toward away over under top bottom
front rear side middle center edge end mile miles feet yards meters kilometers block blocks
go going went gone come coming came move moving stay staying stop stopping wait waiting hold
holding keep keeping leave leaving left arrive arriving arrived return returning run running walk
walking drive driving ride riding fly flying carry carrying bring bringing take taking give
giving send sending get getting find finding found look looking watch watching listen listening
hear hearing heard tell telling told ask asking answer answering call calling called reply
repeat copy read reading write writing check checking confirm confirmed confirm cancel cancelled
meet meeting gather gathering join joining split meet rendezvous assemble regroup evacuate
evacuation evacuating rescue rescued rescuing search searching missing lost trapped stuck
fix fixing fixed repair repaired repairing build building built start started starting turn
turned turning open opened opening close closed closing lock locked unlock block clear cleared
need needs needed want wanted wants spare trade swap share sharing buy sell give borrow lend
have having had make making made use using used work working works broken running out low
enough plenty extra more less none nothing everything something anything all both each every
can cannot cant could would should might must will shall may please thanks thank sorry
hello hi goodbye bye welcome careful watch beware warning alert alarm emergency urgent
immediately quickly slowly quietly carefully hurry rush now asap stand standby copy roger over
out break clear mayday report status update situation
am was were being does doing done didnt dont doesnt isnt arent wasnt wont wouldnt couldnt
shouldnt cant havent hasnt im ive ill id youre youve youll weve well theyre theyve thats whats
heres theres lets
because if then else though although unless whether maybe probably perhaps definitely sure
certain think thought believe guess hope wish wonder feel felt feeling seem seems looks looked
sound sounds heard saw seen see saw show showing showed
about above across after against among around at before behind beside between beyond during
except inside into like near of off onto out outside over past per since through throughout till
toward under until up upon with within without
red blue green yellow white black brown gray grey orange pink purple silver gold dark light
big huge tiny large heavy empty full wide narrow tall deep flat steep rough smooth sharp
hard soft easy difficult hard safe unsafe secure unsecure free busy available ready late early
true false real fake lie truth real alone together apart both either neither
body head face eye eyes ear ears nose mouth teeth neck shoulder arm arms hand hands finger
fingers chest back stomach leg legs knee foot feet toe skin bone bones lung lungs brain
dog dogs cat cats horse horses cow cows cattle pig pigs chicken chickens goat goats sheep deer
bear wolf coyote snake rat rats animal animals
tool tools axe saw hammer nails screws wire cable chain lock key keys map maps paper pen pencil
book books note notes list code word words name names number numbers letter letters message
messages sign signs flag flags light lights lamp mirror
money cash gold silver coin coins price cost worth owe owed pay paid
war fight fighting battle army militia government state federal national guard martial law
curfew order orders rule rules plan plans mission task job duty shift watch patrol posted
post perimeter lookout sentry radio net frequency password phrase countersign signal code
whistle horn bell light flare flash
gallon gallons liter liters pound pounds ounce ounces bag sack case cases pack packs load
loads piece pieces pair pairs dozen half quarter double single both
""").split()

seen = set()
out = []
for word in WORDS:
    if not re.fullmatch(r"[a-z]+('[a-z]+)?", word):
        sys.exit(f"bad dictionary word: {word!r}")
    if word not in seen:
        seen.add(word)
        out.append(word)

target = Path(__file__).resolve().parent.parent / "Packages/DLCore/Sources/DLCore/Resources/dictionary.txt"
target.write_text("\n".join(out) + "\n", encoding="utf-8")
print(f"{len(out)} words -> {target}")
