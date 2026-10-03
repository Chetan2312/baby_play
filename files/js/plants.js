/* ============================================================
   Takatak Zoo — the plants of the jungle walk
   Names in all three languages; facts in English.

     cat     tree | fruit | berry | danger | ground
     eat     "yes"  fruit is eaten (with a grown-up)
             "no"   poisonous or not food — look, don't eat
             "—"    not a food plant
     shows   the close-ups on the plant stage: leaf is always there,
             plus fruit / flower / pod / seeds / berries
   ============================================================ */

export const CATS = {
  tree:   { emoji: "🌳", en: "Jungle tree",     mr: "जंगलातील झाड",  hi: "जंगल का पेड़" },
  fruit:  { emoji: "🥭", en: "Wild fruit tree", mr: "रानमेवा झाड",   hi: "जंगली फल का पेड़" },
  berry:  { emoji: "🫐", en: "Wild berries",    mr: "रानमेवा",       hi: "जंगली बेर-फल" },
  danger: { emoji: "⚠️", en: "Look, don’t eat!", mr: "फक्त बघा, खाऊ नका!", hi: "सिर्फ़ देखो, खाओ मत!" },
  ground: { emoji: "🌱", en: "Ground plant",    mr: "जमिनीवरचे रोप", hi: "ज़मीन का पौधा" },
};

export const PARTS = {
  leaf:    { en: "Leaf",    mr: "पान",   hi: "पत्ता" },
  fruit:   { en: "Fruit",   mr: "फळ",    hi: "फल" },
  flower:  { en: "Flower",  mr: "फूल",   hi: "फूल" },
  pod:     { en: "Pod",     mr: "शेंग",  hi: "फली" },
  seeds:   { en: "Seeds",   mr: "बिया",  hi: "बीज" },
  berries: { en: "Berries", mr: "फळे",   hi: "बेरी" },
  roots:   { en: "Hanging roots", mr: "पारंब्या", hi: "जटाएँ" },
};

export const PLANTS = [
  /* ---------------- jungle trees ---------------- */
  {
    id: "banyan", emoji: "🌳", cat: "tree", eat: "—", shows: ["leaf", "fruit", "roots"],
    name: { en: "Banyan", mr: "वड", hi: "बरगद" },
    info: {
      spot: "A giant, wide tree with roots hanging down from its branches like ropes. The roots reach the ground and become new trunks.",
      season: "Green all year. Small red figs in summer.",
      eaters: "Birds, bats, monkeys and squirrels feast on the figs.",
      uses: "Gives huge shade — villages meet under it.",
      fact: "The banyan is India’s national tree. One banyan in Kolkata is so wide it looks like a whole forest!",
    },
  },
  {
    id: "peepal", emoji: "🌳", cat: "tree", eat: "—", shows: ["leaf", "fruit"],
    name: { en: "Peepal", mr: "पिंपळ", hi: "पीपल" },
    info: {
      spot: "Heart-shaped leaves with a long, thin tail at the tip. The leaves flutter and rustle even when there is hardly any wind.",
      season: "Loses leaves briefly in spring, then shiny pink-red new leaves come.",
      eaters: "Birds and bats eat its tiny figs.",
      uses: "Planted near temples; people sit in its shade.",
      fact: "The Buddha sat under a peepal tree when he found enlightenment — it is also called the Bodhi tree.",
    },
  },
  {
    id: "neem", emoji: "🌳", cat: "tree", eat: "no", shows: ["leaf", "fruit"],
    name: { en: "Neem", mr: "कडुनिंब", hi: "नीम" },
    info: {
      spot: "Each leaf is a stalk with many small pointed leaflets with jagged edges. Leaves taste very bitter.",
      season: "Tiny white scented flowers in spring, yellow-green fruits in summer.",
      eaters: "Birds eat the ripe fruits.",
      uses: "Neem twigs were used as toothbrushes (datun). Dry leaves keep insects away from stored grain.",
      fact: "Neem is so bitter that most insects leave it alone. Don’t eat its fruit.",
    },
  },
  {
    id: "teak", emoji: "🌳", cat: "tree", eat: "—", shows: ["leaf", "flower"],
    name: { en: "Teak", mr: "साग", hi: "सागौन" },
    info: {
      spot: "A tall straight tree with enormous leaves — as big as a newspaper! Rough leaves feel like sandpaper.",
      season: "Loses all its leaves in the dry season; small white flowers in the monsoon.",
      eaters: "Deer and langurs nibble the young leaves.",
      uses: "Its golden wood is strong and does not rot — used for doors, furniture and ships.",
      fact: "Rub a young teak leaf and it leaves red colour on your fingers.",
    },
  },
  {
    id: "sal", emoji: "🌳", cat: "tree", eat: "—", shows: ["leaf", "flower"],
    name: { en: "Sal", mr: "साल", hi: "साल" },
    info: {
      spot: "Tall, straight trunks growing close together, with big shiny oval leaves. Whole forests can be only sal.",
      season: "Creamy flowers in spring and winged seeds that spin like helicopters.",
      eaters: "Elephants, deer and many insects.",
      uses: "Sal leaves are stitched into plates and bowls (pattal, dona). Strong wood for railway sleepers.",
      fact: "Tiger forests like Kanha and Simlipal are full of sal trees.",
    },
  },
  {
    id: "bamboo", emoji: "🎋", cat: "tree", eat: "—", shows: ["leaf"],
    name: { en: "Bamboo", mr: "बांबू", hi: "बाँस" },
    info: {
      spot: "Tall, hollow green poles with rings (nodes), growing in thick clumps. Thin, pointed leaves.",
      season: "Green all year. Many bamboos flower only once in 30–60 years!",
      eaters: "Elephants and pandas love bamboo.",
      uses: "Houses, ladders, baskets, flutes and fences.",
      fact: "Bamboo is actually a giant grass — some kinds grow almost a metre in one day!",
    },
  },
  {
    id: "palash", emoji: "🔥", cat: "tree", eat: "—", shows: ["leaf", "flower"],
    name: { en: "Palash (Flame of the forest)", mr: "पळस", hi: "पलाश" },
    info: {
      spot: "A crooked tree covered in bright orange flowers shaped like a parrot’s beak. Leaves come in threes.",
      season: "Blazes orange in February–March when it has almost no leaves.",
      eaters: "Birds and squirrels sip nectar from the flowers.",
      uses: "Holi colours were once made from its flowers; leaves are used as plates.",
      fact: "When palash flowers, the forest looks like it is on fire — that is why it is called ‘flame of the forest’.",
    },
  },
  {
    id: "semal", emoji: "🌺", cat: "tree", eat: "—", shows: ["leaf", "flower", "seeds"],
    name: { en: "Silk cotton (Semal)", mr: "काटेसावर", hi: "सेमल" },
    info: {
      spot: "A huge tree with a thorny trunk, branches in flat layers, and big red cup-shaped flowers.",
      season: "Red flowers in spring on bare branches; pods burst with white cotton in summer.",
      eaters: "Crows, mynas and monkeys drink the nectar.",
      uses: "The soft cotton was used to fill pillows.",
      fact: "The cotton carries its seeds far away on the wind, like tiny parachutes.",
    },
  },
  {
    id: "mahua", emoji: "🌼", cat: "tree", eat: "—", shows: ["leaf", "flower"],
    name: { en: "Mahua", mr: "मोह", hi: "महुआ" },
    info: {
      spot: "A big shady tree with leaves bunched at the twig ends. In spring, creamy round flowers drop to the ground.",
      season: "Flowers fall in March–April, mostly at night.",
      eaters: "Sloth bears, deer, monkeys and birds all rush to eat the sweet fallen flowers.",
      uses: "Forest villagers collect the flowers and seeds — mahua is very important to them.",
      fact: "In mahua season, bears come out at dawn to eat the fallen flowers.",
    },
  },

  /* ---------------- wild fruit trees ---------------- */
  {
    id: "mango", emoji: "🥭", cat: "fruit", eat: "yes", photo: "pics/mango.webp", shows: ["leaf", "fruit", "flower"],
    name: { en: "Mango", mr: "आंबा", hi: "आम" },
    info: {
      spot: "A dense, dark-green, dome-shaped tree. Long pointed leaves; new leaves are pink-brown. Fruits hang on long stalks.",
      season: "Flowers in winter–spring, mangoes in April–June.",
      eaters: "Monkeys, bats, parrots — and us!",
      uses: "Fruit, pickles, raw-mango drinks; leaves are hung as festive toran.",
      fact: "The mango is India’s national fruit. Wild mangoes are small but very sweet.",
    },
  },
  {
    id: "jackfruit", emoji: "🍈", cat: "fruit", eat: "yes", photo: "pics/jackfruit.webp", shows: ["leaf", "fruit"],
    name: { en: "Jackfruit", mr: "फणस", hi: "कटहल" },
    info: {
      spot: "Huge spiky green fruits growing straight out of the trunk and thick branches. Shiny dark leaves.",
      season: "Fruits from spring to monsoon.",
      eaters: "Elephants, bears, monkeys and people.",
      uses: "Sweet ripe pods, cooked raw jackfruit, roasted seeds.",
      fact: "Jackfruit is the biggest fruit that grows on a tree — one can weigh as much as a child!",
    },
  },
  {
    id: "jamun", emoji: "🫐", cat: "fruit", eat: "yes", shows: ["leaf", "fruit"],
    name: { en: "Jamun", mr: "जांभूळ", hi: "जामुन" },
    info: {
      spot: "A tall evergreen tree with shiny leaves that smell like turpentine when crushed. Clusters of purple-black fruit.",
      season: "Fruits in June–July, at the start of the monsoon.",
      eaters: "Birds, bats, monkeys, bears — and children with purple tongues!",
      uses: "Fruit is eaten fresh; the tree grows near rivers and lakes.",
      fact: "Eat jamun and your tongue turns purple for a while.",
    },
  },
  {
    id: "tamarind", emoji: "🟤", cat: "fruit", eat: "yes", photo: "pics/tamarind.webp", shows: ["leaf", "pod"],
    name: { en: "Tamarind", mr: "चिंच", hi: "इमली" },
    info: {
      spot: "A big spreading tree with feathery leaves made of tiny leaflets, and curved brown pods hanging down.",
      season: "Pods ripen in winter and spring.",
      eaters: "Monkeys, deer and people.",
      uses: "The sour pulp goes into sambar, chutney and sweets.",
      fact: "At night tamarind leaflets fold up as if the tree is going to sleep.",
    },
  },
  {
    id: "amla", emoji: "🟢", cat: "fruit", eat: "yes", shows: ["leaf", "fruit"],
    name: { en: "Amla (Indian gooseberry)", mr: "आवळा", hi: "आँवला" },
    info: {
      spot: "A small tree with feathery leaves of tiny leaflets, and light-green round fruits with faint lines, stuck close to the branches.",
      season: "Fruits in winter.",
      eaters: "Deer, monkeys and people.",
      uses: "Pickles, murabba, juice; very rich in vitamin C.",
      fact: "Amla tastes sour and bitter — but drink water after and your mouth tastes sweet!",
    },
  },
  {
    id: "bael", emoji: "🟡", cat: "fruit", eat: "yes", shows: ["leaf", "fruit"],
    name: { en: "Bael (Wood apple)", mr: "बेल", hi: "बेल" },
    info: {
      spot: "A thorny tree with leaves in threes and hard round fruits like wooden balls.",
      season: "Fruits ripen in summer.",
      eaters: "Monkeys and elephants can crack the hard shell.",
      uses: "The sweet orange pulp makes cool summer sherbet; leaves are offered to Lord Shiva.",
      fact: "The shell is so hard you need to crack it with a stone.",
    },
  },
  {
    id: "gular", emoji: "🔴", cat: "fruit", eat: "yes", shows: ["leaf", "fruit"],
    name: { en: "Cluster fig (Gular)", mr: "उंबर", hi: "गूलर" },
    info: {
      spot: "Bunches of round figs growing right on the trunk and big branches, often near water.",
      season: "Figs almost all year.",
      eaters: "Birds, bats, monkeys, squirrels, deer, fish that catch fallen figs…",
      uses: "Ripe figs are eaten; it tells villagers there is water underground.",
      fact: "Each fig is a closed flower pot — a tiny wasp crawls inside to make seeds.",
    },
  },
  {
    id: "coconut", emoji: "🥥", cat: "fruit", eat: "yes", photo: "pics/coconut.webp", shows: ["leaf", "fruit"],
    name: { en: "Coconut palm", mr: "नारळ", hi: "नारियल" },
    info: {
      spot: "A tall, bending trunk with rings and no branches, and a crown of long feather-like leaves. Coconuts grow in bunches under the leaves.",
      season: "Coconuts all year round.",
      eaters: "Crabs, rats — and people.",
      uses: "Coconut water, coconut, oil, rope from its hair, brooms from its leaves.",
      fact: "A coconut can float across the sea and grow on a new beach.",
    },
  },
  {
    id: "banana", emoji: "🍌", cat: "fruit", eat: "yes", shows: ["leaf", "fruit", "flower"],
    name: { en: "Banana", mr: "केळ", hi: "केला" },
    info: {
      spot: "Huge wide paddle leaves on a soft green stem, and a big bunch of bananas with a purple flower hanging at the end.",
      season: "Fruits all year.",
      eaters: "Elephants, monkeys, bats and birds.",
      uses: "Fruit, cooked raw bananas, banana-leaf plates for meals.",
      fact: "A banana plant is not a tree — it is a giant herb. Wild bananas are full of hard seeds.",
    },
  },

  /* ---------------- wild berries & bushes ---------------- */
  {
    id: "ber", emoji: "🟠", cat: "berry", eat: "yes", shows: ["leaf", "fruit"],
    name: { en: "Ber (Indian jujube)", mr: "बोर", hi: "बेर" },
    info: {
      spot: "A thorny bush or small tree with small round shiny leaves, pale underneath, and little round fruits.",
      season: "Fruits in winter, turning from green to orange-red.",
      eaters: "Birds, jackals, deer, monkeys and children.",
      uses: "Sweet-sour snack, sold by the handful in villages.",
      fact: "In the Ramayana, Shabari tasted each ber to give Lord Ram only the sweetest ones.",
    },
  },
  {
    id: "karonda", emoji: "🫐", cat: "berry", eat: "yes", shows: ["leaf", "berries"],
    name: { en: "Karonda", mr: "करवंद", hi: "करौंदा" },
    info: {
      spot: "A dense bush with sharp paired thorns, small shiny leaves and berries that turn pink, then purple-black.",
      season: "Berries at the start of the monsoon (May–June).",
      eaters: "Birds, bears and hill children.",
      uses: "Ripe berries are eaten; raw ones become pickle and jam.",
      fact: "Karvanda from the Sahyadri hills are the berries Maharashtra kids pick in summer holidays.",
    },
  },
  {
    id: "mulberry", emoji: "🍇", cat: "berry", eat: "yes", shows: ["leaf", "berries"],
    name: { en: "Mulberry", mr: "तुती", hi: "शहतूत" },
    info: {
      spot: "A small tree with heart-shaped, toothed leaves and long bumpy berries that go from green to red to black.",
      season: "Berries in spring.",
      eaters: "Birds, squirrels and children.",
      uses: "Berries are eaten; leaves feed silkworms.",
      fact: "Silk comes from silkworms that eat only mulberry leaves.",
    },
  },
  {
    id: "phalsa", emoji: "🟣", cat: "berry", eat: "yes", shows: ["leaf", "berries"],
    name: { en: "Phalsa", mr: "फालसा", hi: "फालसा" },
    info: {
      spot: "A bush with big round rough leaves and clusters of tiny berries that turn dark purple.",
      season: "Berries in the hot summer (April–June).",
      eaters: "Birds and people.",
      uses: "A cooling summer sherbet.",
      fact: "Phalsa berries are so soft they must be eaten on the day they are picked.",
    },
  },
  {
    id: "sitaphal", emoji: "🍏", cat: "berry", eat: "yes", shows: ["leaf", "fruit"],
    name: { en: "Custard apple (Sitaphal)", mr: "सीताफळ", hi: "शरीफा" },
    info: {
      spot: "A small tree on rocky hills with pale leaves and bumpy green fruits that look like they are made of scales.",
      season: "Fruits after the monsoon (August–October).",
      eaters: "Birds, bats, monkeys and people.",
      uses: "The creamy white pulp is eaten; the black seeds are spat out.",
      fact: "The hills near Pune and Aurangabad are famous for wild sitaphal.",
    },
  },

  /* ---------------- look, don't eat ---------------- */
  {
    id: "lantana", emoji: "🌸", cat: "danger", eat: "no", shows: ["leaf", "flower", "berries"],
    name: { en: "Lantana", mr: "घाणेरी", hi: "लैंटाना" },
    info: {
      spot: "A scratchy bush with small rough leaves and pretty round bunches of tiny flowers — pink, yellow and orange together.",
      season: "Flowers almost all year; small black berries.",
      eaters: "Butterflies love the flowers; some birds eat the berries.",
      uses: "None for us — it takes over forests and pushes out other plants.",
      fact: "Lantana is beautiful but its leaves and green berries are poisonous. Look, don’t eat!",
    },
  },
  {
    id: "datura", emoji: "🤍", cat: "danger", eat: "no", shows: ["leaf", "flower", "fruit"],
    name: { en: "Datura", mr: "धोतरा", hi: "धतूरा" },
    info: {
      spot: "A low bush with big white trumpet-shaped flowers and round green fruits covered in spikes.",
      season: "Flowers open in the evening, mostly in the monsoon.",
      eaters: "Moths visit the flowers at night.",
      uses: "Offered at temples — but never eaten.",
      fact: "Every part of datura is very poisonous. Never touch your mouth after touching it!",
    },
  },
  {
    id: "gunja", emoji: "🔴", cat: "danger", eat: "no", shows: ["leaf", "seeds"],
    name: { en: "Rosary pea (Gunja)", mr: "गुंज", hi: "रत्ती" },
    info: {
      spot: "A thin climbing vine with feathery leaves and pods that open to show shiny red seeds, each with a black spot.",
      season: "Pods open in winter.",
      eaters: "Nothing should — the seeds are among the most poisonous in the world.",
      uses: "Long ago, goldsmiths used the seeds as tiny weights (one ‘ratti’).",
      fact: "The seeds look like beautiful beads, but even one chewed seed is dangerous. Never put them in your mouth.",
    },
  },
  {
    id: "mushroom", emoji: "🍄", cat: "danger", eat: "no", shows: [],
    name: { en: "Wild mushrooms", mr: "अळंबी", hi: "कुकुरमुत्ता" },
    info: {
      spot: "Umbrella-shaped caps popping up on logs and wet soil after rain — red with white spots, brown, white or yellow.",
      season: "Monsoon.",
      eaters: "Slugs, insects and some animals.",
      uses: "They break down dead wood and leaves into soil.",
      fact: "Mushrooms are not plants — they are fungi. Many wild ones are deadly, so never eat a mushroom you find.",
    },
  },

  /* ---------------- ground plants ---------------- */
  {
    id: "mimosa", emoji: "🌿", cat: "ground", eat: "—", shows: ["leaf", "flower"],
    name: { en: "Touch-me-not", mr: "लाजाळू", hi: "छुईमुई" },
    info: {
      spot: "A low creeping plant with feathery leaves and fluffy pink ball flowers. Touch a leaf and it folds shut!",
      season: "Flowers in the monsoon and after.",
      eaters: "Deer and cattle nibble it, but its stems have tiny thorns.",
      uses: "A favourite plant to play with — gently.",
      fact: "It folds its leaves in a second to scare away hungry animals. Tap it and see!",
    },
  },
  {
    id: "fern", emoji: "🌿", cat: "ground", eat: "—", shows: [],
    name: { en: "Fern", mr: "नेचे", hi: "फ़र्न" },
    info: {
      spot: "Soft feathery leaves (fronds) in shady, wet places. New fronds come out rolled up like a spring.",
      season: "Fresh and green in the monsoon.",
      eaters: "Some insects and deer.",
      uses: "They keep the forest floor cool and moist.",
      fact: "Ferns have no flowers or seeds. They grew on Earth even before the dinosaurs!",
    },
  },
];
