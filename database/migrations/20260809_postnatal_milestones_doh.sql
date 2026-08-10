-- InaAgapay: seed the postnatal milestone catalogue from the DOH ECCD book
--
-- SOURCE
-- ------
-- Department of Health, "Gabay Para sa Bata" — the Early Childhood Care and
-- Development (ECCD) home-based record given to parents at the health centre,
-- covering birth to five years. The Cebuano edition ships in this repository
-- at inaagapay_flutter_v2/assets/pdf/DOH.pdf (140 pages), so every line below
-- is traceable to a page in a file the panel can open.
--
-- The DOH set is the CDC "Learn the Signs. Act Early." milestone list adopted
-- for Philippine use. Two independent checks confirmed the alignment before
-- anything was written: the 2-month entries match ("calms when spoken to or
-- picked up", "makes sounds other than crying"), and so do the 5-year ones
-- ("counts to ten", "hops on one foot", "writes some letters in their name").
--
-- Page references, from the book's own contents page:
--
--     2 months   p43-44      15 months  p76-77      3 years   p97-98
--     4 months   p46-47      18 months  p81-82      4 years   p103-104
--     6 months   p51-52      2 years    p88-89      5 years   p109-110
--     9 months   p64-65      30 months  p91-92
--     12 months  p68-69
--
--
-- A FIFTH DOMAIN
-- --------------
-- 20260808_baby_book_foundation allowed four postnatal categories — motor,
-- language, social, cognitive — the CDC domains. The DOH book carries a fifth,
-- "Pagtabang sa Kaugalingon" (self-help), used at 2, 3 and 4 years for eating
-- with a spoon, dressing, and pouring water. Dropping those entries to fit the
-- constraint would have quietly edited the source, so the constraint changes
-- instead.
--
--
-- WORDING
-- -------
-- English is the standard published phrasing of the same milestones rather
-- than a literal translation of the Cebuano, so that a midwife comparing this
-- screen against an English DOH or CDC card sees the same sentences.
--
-- Filipino stays NULL, as it did for the prenatal seed. These are read by
-- mothers about their own children, and a Cebuano-to-Tagalog machine
-- translation is worse than an English fallback. They want a Tagalog speaker.
--
--
-- WHAT THIS IS NOT
-- ----------------
-- A screening tool. The book frames these as what a caregiver may expect and
-- prompts "Aduna ka bay mga pangutana kabahin sa pagtubo ni baby?" — do you
-- have questions about your baby's growth — pointing the parent at the health
-- worker. Nothing here should tell a mother her child is delayed; an unrecorded
-- milestone reads "not recorded", never "missed", the same rule the prenatal
-- side already follows.

BEGIN;

-- ---------------------------------------------------------------------------
-- Allow the DOH self-help domain
-- ---------------------------------------------------------------------------

ALTER TABLE public.milestone_templates
  DROP CONSTRAINT IF EXISTS milestone_templates_category_check;

ALTER TABLE public.milestone_templates
  ADD CONSTRAINT milestone_templates_category_check CHECK (
    (
      phase = 'prenatal'
      AND category = ANY (
        ARRAY ['development', 'movement', 'checkup',
               'ultrasound', 'trimester', 'personal_memory']
      )
    )
    OR (
      phase = 'postnatal'
      AND category = ANY (
        ARRAY ['motor', 'language', 'social', 'cognitive', 'self_help']
      )
    )
  );

-- ---------------------------------------------------------------------------
-- The catalogue
-- ---------------------------------------------------------------------------
-- owner defaults to 'baby': every entry here is the child's own story.
-- sort_order is age * 100 + a domain offset, so a mixed query still lists in
-- a sensible reading order without a second sort key.

INSERT INTO public.milestone_templates
    (template_key, phase, category, age_months_target, title_en, sort_order)
VALUES
-- 2 months (p43-44)
('pn-02m-soc-calms',     'postnatal','social',    2,'Calms down when spoken to or picked up',                  201),
('pn-02m-soc-face',      'postnatal','social',    2,'Looks at your face',                                      202),
('pn-02m-soc-happy',     'postnatal','social',    2,'Seems happy to see you when you walk up',                  203),
('pn-02m-soc-smile',     'postnatal','social',    2,'Smiles when you talk to or smile at them',                 204),
('pn-02m-lang-sounds',   'postnatal','language',  2,'Makes sounds other than crying',                           211),
('pn-02m-lang-loud',     'postnatal','language',  2,'Reacts to loud sounds',                                    212),
('pn-02m-cog-watch',     'postnatal','cognitive', 2,'Watches you as you move',                                  221),
('pn-02m-cog-toy',       'postnatal','cognitive', 2,'Looks at a toy for several seconds',                       222),
('pn-02m-mot-head',      'postnatal','motor',     2,'Holds head up when on their tummy',                        231),
('pn-02m-mot-limbs',     'postnatal','motor',     2,'Moves both arms and both legs',                            232),
('pn-02m-mot-hands',     'postnatal','motor',     2,'Opens their hands briefly',                                233),
('pn-02m-mot-suck',      'postnatal','motor',     2,'Can suck and swallow liquid',                              234),

-- 4 months (p46-47)
('pn-04m-soc-attn',      'postnatal','social',    4,'Smiles on their own to get your attention',                401),
('pn-04m-soc-chuckle',   'postnatal','social',    4,'Chuckles when you try to make them laugh',                 402),
('pn-04m-soc-keep',      'postnatal','social',    4,'Looks, moves, or makes sounds to keep your attention',     403),
('pn-04m-lang-coo',      'postnatal','language',  4,'Makes cooing sounds like "oooo" and "aahh"',               411),
('pn-04m-lang-back',     'postnatal','language',  4,'Makes sounds back when you talk to them',                  412),
('pn-04m-lang-turn',     'postnatal','language',  4,'Turns their head toward the sound of your voice',          413),
('pn-04m-cog-hungry',    'postnatal','cognitive', 4,'Opens their mouth when hungry and sees the breast',        421),
('pn-04m-cog-hands',     'postnatal','cognitive', 4,'Looks at their hands with interest',                       422),
('pn-04m-cog-follow',    'postnatal','cognitive', 4,'Follows moving things with their eyes',                    423),
('pn-04m-mot-steady',    'postnatal','motor',     4,'Holds their head steady without support when held',        431),
('pn-04m-mot-swing',     'postnatal','motor',     4,'Uses their arm to swing at toys',                          432),
('pn-04m-mot-mouth',     'postnatal','motor',     4,'Brings their hands to their mouth',                        433),
('pn-04m-mot-elbows',    'postnatal','motor',     4,'Pushes up onto their elbows when on their tummy',          434),
('pn-04m-mot-hold',      'postnatal','motor',     4,'Holds a toy when you put it in their hand',                435),

-- 6 months (p51-52)
('pn-06m-soc-familiar',  'postnatal','social',    6,'Knows familiar people',                                    601),
('pn-06m-soc-mirror',    'postnatal','social',    6,'Likes to look at themselves in a mirror',                  602),
('pn-06m-soc-laugh',     'postnatal','social',    6,'Laughs',                                                   603),
('pn-06m-lang-turns',    'postnatal','language',  6,'Takes turns making sounds with you',                       611),
('pn-06m-lang-rasp',     'postnatal','language',  6,'Blows raspberries',                                        612),
('pn-06m-lang-squeal',   'postnatal','language',  6,'Makes squealing noises',                                   613),
('pn-06m-cog-mouth',     'postnatal','cognitive', 6,'Puts things in their mouth to explore them',               621),
('pn-06m-cog-reach',     'postnatal','cognitive', 6,'Reaches to grab a toy they want',                          622),
('pn-06m-cog-lips',      'postnatal','cognitive', 6,'Closes their lips to show they do not want more food',     623),
('pn-06m-mot-roll',      'postnatal','motor',     6,'Rolls from their tummy onto their back',                   631),
('pn-06m-mot-push',      'postnatal','motor',     6,'Pushes up with straight arms when on their tummy',         632),
('pn-06m-mot-lean',      'postnatal','motor',     6,'Leans on their hands for support when sitting',            633),

-- 9 months (p64-65)
('pn-09m-soc-shy',       'postnatal','social',    9,'Is shy, clingy, or fearful around people they do not know',901),
('pn-09m-soc-express',   'postnatal','social',    9,'Shows several expressions — happy, sad, angry, surprised', 902),
('pn-09m-soc-name',      'postnatal','social',    9,'Looks when you call their name',                           903),
('pn-09m-soc-leave',     'postnatal','social',    9,'Reacts when you leave — looks, reaches, or cries',         904),
('pn-09m-soc-peekaboo',  'postnatal','social',    9,'Smiles or laughs when you play peek-a-boo',                905),
('pn-09m-lang-babble',   'postnatal','language',  9,'Makes sounds like "mamamama" and "babababa"',              911),
('pn-09m-lang-arms',     'postnatal','language',  9,'Lifts their arms up to be picked up',                      912),
('pn-09m-lang-body',     'postnatal','language',  9,'Uses their body to show you what they want',               913),
('pn-09m-cog-hidden',    'postnatal','cognitive', 9,'Looks for things they see you hide',                       921),
('pn-09m-cog-bang',      'postnatal','cognitive', 9,'Bangs two things together',                                922),
('pn-09m-mot-situp',     'postnatal','motor',     9,'Gets to a sitting position by themselves',                 931),
('pn-09m-mot-transfer',  'postnatal','motor',     9,'Moves things from one hand to the other',                  932),
('pn-09m-mot-rake',      'postnatal','motor',     9,'Uses their fingers to rake food toward themselves',        933),
('pn-09m-mot-sit',       'postnatal','motor',     9,'Sits without support',                                     934),

-- 12 months (p68-69)
('pn-12m-soc-games',     'postnatal','social',   12,'Plays games with you, like pat-a-cake',                   1201),
('pn-12m-lang-wave',     'postnatal','language', 12,'Waves bye-bye',                                           1211),
('pn-12m-lang-mama',     'postnatal','language', 12,'Calls a parent "mama" or "dada"',                         1212),
('pn-12m-lang-no',       'postnatal','language', 12,'Understands "no" and pauses briefly when you say it',     1213),
('pn-12m-cog-container', 'postnatal','cognitive',12,'Puts something into a container, like a block in a cup',  1221),
('pn-12m-cog-hide',      'postnatal','cognitive',12,'Looks for things you hide, like a toy under a blanket',   1222),
('pn-12m-mot-pullup',    'postnatal','motor',    12,'Pulls themselves up to stand',                            1231),
('pn-12m-mot-cruise',    'postnatal','motor',    12,'Walks while holding on to furniture',                     1232),
('pn-12m-mot-cup',       'postnatal','motor',    12,'Drinks from a cup without a lid as you hold it',          1233),
('pn-12m-mot-pincer',    'postnatal','motor',    12,'Picks up small things between thumb and pointer finger',  1234),

-- 15 months (p76-77)
('pn-15m-soc-copy',      'postnatal','social',   15,'Copies other children while playing',                     1501),
('pn-15m-soc-show',      'postnatal','social',   15,'Shows you an object they like',                            1502),
('pn-15m-soc-clap',      'postnatal','social',   15,'Claps when they are excited',                              1503),
('pn-15m-soc-hug-toy',   'postnatal','social',   15,'Hugs a stuffed toy or doll',                               1504),
('pn-15m-soc-affection', 'postnatal','social',   15,'Shows affection with hugs or kisses',                      1505),
('pn-15m-lang-words',    'postnatal','language', 15,'Tries to say one or two words besides "mama" or "dada"',   1511),
('pn-15m-lang-name-obj', 'postnatal','language', 15,'Looks at a familiar object when you name it',              1512),
('pn-15m-lang-follow',   'postnatal','language', 15,'Follows directions given with both a gesture and words',   1513),
('pn-15m-cog-use',       'postnatal','cognitive',15,'Tries to use things properly, like a phone, cup, or book', 1521),
('pn-15m-cog-stack',     'postnatal','cognitive',15,'Stacks at least two small objects',                        1522),
('pn-15m-mot-steps',     'postnatal','motor',    15,'Takes a few steps on their own',                           1531),
('pn-15m-mot-feed',      'postnatal','motor',    15,'Uses their fingers to feed themselves',                    1532),

-- 18 months (p81-82)
('pn-18m-soc-away',      'postnatal','social',   18,'Moves away from you but looks back to be sure you are close',1801),
('pn-18m-soc-point',     'postnatal','social',   18,'Points to show you something interesting',                 1802),
('pn-18m-soc-wash',      'postnatal','social',   18,'Puts their hands out to be washed',                        1803),
('pn-18m-soc-book',      'postnatal','social',   18,'Looks at a few pages in a book with you',                  1804),
('pn-18m-soc-dress',     'postnatal','social',   18,'Helps you dress them, like pushing an arm through a sleeve',1805),
('pn-18m-lang-three',    'postnatal','language', 18,'Tries to say three or more words besides "mama" or "dada"',1811),
('pn-18m-lang-onestep',  'postnatal','language', 18,'Follows a one-step direction given without a gesture',     1812),
('pn-18m-cog-chores',    'postnatal','cognitive',18,'Copies you doing chores',                                  1821),
('pn-18m-cog-play',      'postnatal','cognitive',18,'Plays with toys in a simple way, like pushing a toy car',  1822),
('pn-18m-mot-walk',      'postnatal','motor',    18,'Walks without holding on to anyone',                       1831),
('pn-18m-mot-scribble',  'postnatal','motor',    18,'Scribbles',                                                1832),
('pn-18m-mot-cup',       'postnatal','motor',    18,'Drinks from a cup without a lid, spilling sometimes',      1833),
('pn-18m-mot-fingers',   'postnatal','motor',    18,'Feeds themselves with their fingers',                      1834),

-- 2 years (p88-89)
('pn-24m-soc-notices',   'postnatal','social',   24,'Notices when others are hurt or upset',                    2401),
('pn-24m-soc-checks',    'postnatal','social',   24,'Looks at your face to see how to react in a new situation', 2402),
('pn-24m-lang-two',      'postnatal','language', 24,'Says at least two words together, like "more milk"',       2411),
('pn-24m-lang-body',     'postnatal','language', 24,'Points to at least two body parts when you ask',           2412),
('pn-24m-lang-gestures', 'postnatal','language', 24,'Uses more gestures than waving and pointing',              2413),
('pn-24m-cog-twohands',  'postnatal','cognitive',24,'Holds something in one hand while using the other',        2421),
('pn-24m-cog-switches',  'postnatal','cognitive',24,'Tries switches, knobs, or buttons on a toy',               2422),
('pn-24m-cog-multitoy',  'postnatal','cognitive',24,'Plays with more than one toy at the same time',            2423),
('pn-24m-mot-kick',      'postnatal','motor',    24,'Kicks a ball',                                             2431),
('pn-24m-mot-run',       'postnatal','motor',    24,'Runs',                                                     2432),
('pn-24m-mot-stairs',    'postnatal','motor',    24,'Walks up a few stairs without help',                       2433),
('pn-24m-self-spoon',    'postnatal','self_help',24,'Eats with a spoon, spilling sometimes',                    2441),

-- 30 months (p91-92)
('pn-30m-soc-alongside', 'postnatal','social',   30,'Plays next to other children, and sometimes with them',    3001),
('pn-30m-soc-showoff',   'postnatal','social',   30,'Shows you what they can do, saying "look at me"',          3002),
('pn-30m-soc-routine',   'postnatal','social',   30,'Follows simple routines, like putting toys away when told',3003),
('pn-30m-lang-fifty',    'postnatal','language', 30,'Says about fifty words',                                   3011),
('pn-30m-lang-action',   'postnatal','language', 30,'Says two or more words with one action word, like "dog run"',3012),
('pn-30m-lang-names',    'postnatal','language', 30,'Names things in a book when you point and ask',            3013),
('pn-30m-lang-pronouns', 'postnatal','language', 30,'Says words like "I", "me", and "we"',                      3014),
('pn-30m-cog-pretend',   'postnatal','cognitive',30,'Uses things to pretend, like feeding a block to a doll',   3021),
('pn-30m-cog-solve',     'postnatal','cognitive',30,'Solves simple problems, like standing on a stool to reach',3022),
('pn-30m-cog-twostep',   'postnatal','cognitive',30,'Follows two-step instructions',                            3023),
('pn-30m-cog-colour',    'postnatal','cognitive',30,'Knows at least one colour when you ask',                   3024),
('pn-30m-mot-twist',     'postnatal','motor',    30,'Uses their hands to twist things, like a doorknob or lid', 3031),
('pn-30m-mot-jump',      'postnatal','motor',    30,'Jumps off the ground with both feet',                      3032),
('pn-30m-mot-pages',     'postnatal','motor',    30,'Turns book pages one at a time when you read together',    3033),

-- 3 years (p97-98)
('pn-36m-soc-calm',      'postnatal','social',   36,'Calms down within about ten minutes after you leave them', 3601),
('pn-36m-soc-joins',     'postnatal','social',   36,'Notices other children and joins them to play',            3602),
('pn-36m-lang-convo',    'postnatal','language', 36,'Talks with you in at least two back-and-forth exchanges',  3611),
('pn-36m-lang-questions','postnatal','language', 36,'Asks who, what, where, or why questions',                  3612),
('pn-36m-lang-action',   'postnatal','language', 36,'Says what is happening in a picture, like running or eating',3613),
('pn-36m-lang-name',     'postnatal','language', 36,'Says their first name when asked',                         3614),
('pn-36m-lang-clear',    'postnatal','language', 36,'Talks well enough for others to understand most of the time',3615),
('pn-36m-cog-circle',    'postnatal','cognitive',36,'Draws a circle when you show them how',                    3621),
('pn-36m-cog-hot',       'postnatal','cognitive',36,'Avoids touching hot objects when you warn them',           3622),
('pn-36m-mot-string',    'postnatal','motor',    36,'Strings items together, like large beads',                 3631),
('pn-36m-self-clothes',  'postnatal','self_help',36,'Puts on some clothes by themselves',                       3641),
('pn-36m-self-fork',     'postnatal','self_help',36,'Uses a fork',                                              3642),

-- 4 years (p103-104)
('pn-48m-soc-pretend',   'postnatal','social',   48,'Pretends to be someone else while playing',                4801),
('pn-48m-soc-asks-play', 'postnatal','social',   48,'Asks to go and play with other children',                  4802),
('pn-48m-soc-comforts',  'postnatal','social',   48,'Comforts others who are hurt or sad',                      4803),
('pn-48m-soc-danger',    'postnatal','social',   48,'Avoids danger, like not jumping from somewhere high',      4804),
('pn-48m-soc-helper',    'postnatal','social',   48,'Likes to be a helper',                                     4805),
('pn-48m-soc-adapts',    'postnatal','social',   48,'Behaves differently depending on where they are',          4806),
('pn-48m-lang-four',     'postnatal','language', 48,'Says sentences with four or more words',                   4811),
('pn-48m-lang-song',     'postnatal','language', 48,'Says some words from a song, story, or nursery rhyme',     4812),
('pn-48m-lang-day',      'postnatal','language', 48,'Talks about at least one thing that happened in their day',4813),
('pn-48m-lang-answers',  'postnatal','language', 48,'Answers simple questions, like what a crayon is for',      4814),
('pn-48m-cog-colours',   'postnatal','cognitive',48,'Names a few colours',                                      4821),
('pn-48m-cog-story',     'postnatal','cognitive',48,'Tells what comes next in a story they know well',          4822),
('pn-48m-cog-person',    'postnatal','cognitive',48,'Draws a person with three or more body parts',             4823),
('pn-48m-mot-catch',     'postnatal','motor',    48,'Catches a large ball most of the time',                    4831),
('pn-48m-mot-unbutton',  'postnatal','motor',    48,'Unbuttons some buttons',                                   4832),
('pn-48m-mot-grip',      'postnatal','motor',    48,'Holds a crayon between fingers and thumb, not in a fist',  4833),
('pn-48m-self-serve',    'postnatal','self_help',48,'Serves themselves food or pours water, with an adult nearby',4841),

-- 5 years (p109-110)
('pn-60m-soc-rules',     'postnatal','social',   60,'Follows rules or takes turns when playing with others',    6001),
('pn-60m-soc-performs',  'postnatal','social',   60,'Sings, dances, or acts for you',                           6002),
('pn-60m-soc-chores',    'postnatal','social',   60,'Does simple chores at home, like clearing the table',      6003),
('pn-60m-lang-story',    'postnatal','language', 60,'Tells a story they made up with at least two events',      6011),
('pn-60m-lang-book',     'postnatal','language', 60,'Answers simple questions about a book or story',           6012),
('pn-60m-lang-convo',    'postnatal','language', 60,'Keeps a conversation going with more than three exchanges',6013),
('pn-60m-lang-rhyme',    'postnatal','language', 60,'Uses or recognises simple rhymes',                         6014),
('pn-60m-cog-count',     'postnatal','cognitive',60,'Counts to ten',                                            6021),
('pn-60m-cog-numbers',   'postnatal','cognitive',60,'Names some numbers between one and five when you point',   6022),
('pn-60m-cog-time',      'postnatal','cognitive',60,'Uses words about time, like yesterday, morning, or night', 6023),
('pn-60m-cog-attention', 'postnatal','cognitive',60,'Pays attention for five to ten minutes during an activity',6024),
('pn-60m-cog-writes',    'postnatal','cognitive',60,'Writes some letters in their name',                        6025),
('pn-60m-cog-letters',   'postnatal','cognitive',60,'Names some letters when you point to them',                6026),
('pn-60m-mot-button',    'postnatal','motor',    60,'Buttons some buttons',                                     6031),
('pn-60m-mot-hop',       'postnatal','motor',    60,'Hops on one foot',                                         6032)

ON CONFLICT (template_key) DO UPDATE SET
    phase             = EXCLUDED.phase,
    category          = EXCLUDED.category,
    age_months_target = EXCLUDED.age_months_target,
    title_en          = EXCLUDED.title_en,
    sort_order        = EXCLUDED.sort_order;

COMMIT;
