# Solira — a constructed Romance language

**Solira** (*la lingua solira*) is a small, fully regular Romance conlang built
for this project. Its vocabulary and grammar are blended from its three parent
languages:

- **Spanish** — most of the core vocabulary and the two-copula system
  (*eser* / *star*, cf. *ser* / *estar*), the *no* negator, penultimate stress.
- **French** — a slice of the lexicon (*jorno* < *jour*, *arbre*, *fenetra* <
  *fenêtre*, *travalyo* < *travail*), the *esk* question particle (< *est-ce
  que*), the *va + infinitive* future.
- **English** — an analytic bias: rigid SVO order, periphrastic tenses built
  from auxiliaries, and English loans naturalised to Solira spelling
  (*telefon*, *tren*, *makina*).

The design goal is **regularity**. Almost every word inflects by rule, with
only four irregular auxiliaries. That is what lets a ~1.1M-parameter model
learn to speak it from a synthetic corpus.

---

## 1. Phonology & orthography

Solira is written phonemically — one letter, one sound, no silent letters.

- **Vowels:** `a e i o u` (pure, as in Spanish).
- **Consonants:** `p b t d k g f v s z m n l r`, glides `y j`, and the digraphs
  `ch` (as in English *church*), `ny` (= Spanish ñ), `ly` (palatal l).
- The alphabet deliberately omits `c q w x` and standalone `h`; `k` and `s` do
  the work of the hard/soft *c*.
- Consonant + `l`/`r` clusters are allowed (*pl, pr, tr, br, fl, gr, …*).
- **Stress** is penultimate by default. The only accented forms are two
  interjections (*salú*, *asé*), where the accent marks final stress.

Syllables are simple (C)(l/r)V(C); words end in a vowel or `n s r l z`. The
result reads unmistakably Romance and keeps the character set tiny (~40
letters), which the tokenizer and model both benefit from.

---

## 2. Nouns

Every noun has a **gender** (masculine / feminine) and forms its **plural** by
rule:

- ends in a vowel → add **-s**  (*kasa → kasas*, *gato → gatos*)
- ends in a consonant → add **-es**  (*flor → flores*, *pais → paises*)

**Articles**

| | m.sg | f.sg | pl |
|---|---|---|---|
| definite | le | la | les |
| indefinite | un | una | unes |

---

## 3. Adjectives

Adjectives **follow the noun** and agree with it. Those ending in `-o`/`-a`
mark gender (`o` ↔ `a`); all others are gender-invariant. Plurals follow the
noun rule.

**Agreement** — *gato* (m) 'cat', adj *negro* 'black':

- singular: **le gato negro**
- plural: **les gatos negros**

*flor* (f) 'flower', adj *belo* 'beautiful':

- singular: **la flor bela**
- plural: **les flores belas**

Adverbs can be derived from adjectives with **-mente** (*klaro → klaramente*
'clearly', *rapide → rapidemente* 'quickly').

---

## 4. Pronouns, possessives, demonstratives

**Subject pronouns:** yo (I), tu (you sg), el / ela (he / she), noi (we),
voi (you pl), eli / elas (they). Solira is **pro-drop**: the subject pronoun is
freely omitted because the verb ending already marks person.

**Object pronouns** (pre-verbal): me, te, lo / la, nos, vos, los / las.
*Yo te amo.* — I love you.

**Possessives** (before the noun, agree in number): mi(s), tu(s), su(s), nos,
vos, lor. *mi kasa* (my house), *sus fijos* (his/her children).

**Demonstratives** (agree in gender + number): *este / esta* (this),
*akel / akela* (that). *akela person* — that person.

---

## 5. Verbs

Infinitives end in **-ar / -er / -ir**. The class selects a theme vowel
(a / e / i); person endings are otherwise identical across classes.

**Present indicative (regular)**

| person | kantar (sing) | komer (eat) | dormir (sleep) |
|---|---|---|---|
| yo (1sg) | kanto | komo | dormo |
| tu (2sg) | kantas | komes | dormis |
| el/ela (3sg) | kanta | kome | dormi |
| noi (1pl) | kantamos | komemos | dormimos |
| voi (2pl) | kantatz | kometz | dormitz |
| eli (3pl) | kantan | komen | dormin |

Only four verbs are irregular — and they double as the auxiliaries that build
the other tenses:

**Present indicative (irregular auxiliaries)**

| person | eser (be) | star (be) | avir (have) | var (go) |
|---|---|---|---|---|
| yo (1sg) | so | sto | ai | vo |
| tu (2sg) | es | stas | as | vas |
| el/ela (3sg) | es | sta | a | va |
| noi (1pl) | somos | stamos | amos | vamos |
| voi (2pl) | sotz | statz | atz | vatz |
| eli (3pl) | son | stan | an | van |

*eser* is the copula of identity/essence (Spanish *ser*); *star* is the copula
of state/location (Spanish *estar*).

**Imperfect (past descriptive / habitual)** — regular: stem + theme + *va-*:

| person | kantar | komer | eser |
|---|---|---|---|
| yo (1sg) | kantava | komeva | era |
| tu (2sg) | kantavas | komevas | eras |
| el/ela (3sg) | kantava | komeva | era |
| noi (1pl) | kantavamos | komevamos | eramos |
| voi (2pl) | kantavatz | komevatz | eratz |
| eli (3pl) | kantavan | komevan | eran |

**Non-finite & derived forms** (regular):

- *kantar*: participle **kantat**, gerund **kantando**, imperative **kanta / kantatz**
- *komer*: participle **komet**, gerund **komendo**, imperative **kome / kometz**
- *dormir*: participle **dormit**, gerund **dormindo**, imperative **dormi / dormitz**

**Periphrastic tenses** (English/French-style, built from auxiliaries):

| tense | pattern | example | gloss |
|---|---|---|---|
| perfect / past | *avir* + participle | **yo ai kantat** | I sang / have sung |
| future | *var* + infinitive | **yo vo kantar** | I will sing |
| progressive | *star* + gerund | **yo sto kantando** | I am singing |
| modal | *poder / dever / volir* + infinitive | **yo volo kantar** | I want to sing |

---

## 6. Syntax

Word order is **SVO** and fixed.

- **Copula (identity):** *La fema es un mestre.* — The woman is a teacher.
- **Copula (state/location):** *Le libro sta sur la tabla.* — The book is on the table.
- **Transitive:** *Le gato negro mira la ave.* — The black cat watches the bird.
- **Negation** — *no* before the verb: *Yo no komo karne.* — I don't eat meat.
- **Existential** — impersonal *ai* ('there is/are'): *En le jardin ai tre flores rojas.* — In the garden there are three red flowers.
- **Yes/no question** — particle *esk* + statement + `?`: *Esk tu konoses mi madre?* — Do you know my mother?
- **Wh-question:** *Onde sta le libro?* (Where is the book?) · *Ki es akela person?* (Who is that person?) · *Kuantos gatos ai aki?* (How many cats are here?)
- **Subordination** — *ke* 'that', *kuando* 'when', *porke* 'because', *si* 'if':
  *Yo penso ke le mundo es belo.* — I think that the world is beautiful.
  *Kuando le sol brilava, noi eramos felises.* — When the sun was shining, we were happy.

### Worked examples

| Solira | English |
|---|---|
| Le gato negro dormi sur la tabla. | The black cat sleeps on the table. |
| La fema ama sus fijos. | The woman loves her children. |
| Yo ai komet le pan. | I ate the bread. |
| Noi vamos viajar a la sivda deman. | We will travel to the city tomorrow. |
| Le sol sta brilando en le sielo. | The sun is shining in the sky. |
| Tu no podes dormir aki. | You can't sleep here. |
| — Salú! Komo estas? — Yo so muy bien, grasi. | — Hi! How are you? — I'm very well, thanks. |

---

## 7. Numerals

0–10: zero, un, du, tre, katr, sink, sis, set, ot, nov, dis.
Teens: onze, doze, treze, katorze, kinze, dissis, disset, disot, disnov.
Tens: vint, trenta, karanta, sinkanta, sesanta, setanta, otanta, novanta.
Hundreds/thousand: sento, mil. Compounds join with a hyphen: *vint-tre* (23),
*novanta-nov* (99); *du sento trenta-katr* (234).

Cardinals precede the noun, which is plural for any count above one:
*un gato*, *tre gatos*, *sento libros*.

---

## Dictionary

_Auto-generated from `src/lexicon.py`: 156 nouns, 60 adjectives, 75 verbs, plus function words._


### Nouns (by semantic class)

**human** — *ome* (m) man, *fema* (f) woman, *enfant* (m) child, *amiko* (m) friend (m), *amika* (f) friend (f), *padre* (m) father, *madre* (f) mother, *fijo* (m) son, *fija* (f) daughter, *frate* (m) brother, *sore* (f) sister, *rey* (m) king, *reina* (f) queen, *mestre* (m) teacher, *studen* (m) student, *doktor* (m) doctor, *vesin* (m) neighbor, *poeta* (m) poet, *jente* (f) people, folk

**animal** — *gato* (m) cat, *kan* (m) dog, *kavalo* (m) horse, *ave* (f) bird, *pese* (m) fish, *leon* (m) lion, *lobo* (m) wolf, *oso* (m) bear, *vaka* (f) cow, *ovela* (f) sheep, *abela* (f) bee, *mariposa* (f) butterfly

**nature** — *sol* (m) sun, *luna* (f) moon, *strela* (f) star, *sielo* (m) sky, *mar* (m) sea, *tera* (f) earth, land, *mundo* (m) world, *montanya* (f) mountain, *rio* (m) river, *lago* (m) lake, *foresta* (f) forest, *arbre* (m) tree, *flor* (f) flower, *folya* (f) leaf, *erba* (f) grass, *piedra* (f) stone, *fuego* (m) fire, *agua* (f) water, *vento* (m) wind, *ploja* (f) rain, *neve* (f) snow, *nube* (f) cloud, *luz* (f) light

**place** — *kasa* (f) house, *sivda* (f) city, *pais* (m) country, *strada* (f) street, road, *kamin* (m) path, way, *plaza* (f) square, *mercato* (m) market, *skola* (f) school, *jardin* (m) garden, *kampo* (m) field, countryside, *porta* (f) door, *fenetra* (f) window, *tabla* (f) table, *sila* (f) chair, *leto* (m) bed, *muro* (m) wall, *palas* (m) palace, *tore* (f) tower, *ponte* (m) bridge

**thing** — *libro* (m) book, *palabra* (f) word, *lingua* (f) language, tongue, *nome* (m) name, *letra* (f) letter, *papel* (m) paper, *plume* (f) pen, feather, *kopa* (f) cup, *plato* (m) plate, dish, *moneda* (f) coin, money, *oro* (m) gold, *fero* (m) iron, *ropa* (f) clothes, *sapato* (m) shoe, *chapel* (m) hat, *klave* (f) key, *barka* (f) boat, *nave* (f) ship, *karo* (m) car, cart, *tren* (m) train, *makina* (f) machine, *telefon* (m) telephone

**food** — *pan* (m) bread, *vino* (m) wine, *kafe* (m) coffee, *lete* (m) milk, *fruta* (f) fruit, *pomo* (m) apple, *keso* (m) cheese, *sukro* (m) sugar, *sal* (m) salt, *karne* (f) meat, *sopa* (f) soup

**body** — *man* (f) hand, *brase* (m) arm, *pede* (m) foot, *gamba* (f) leg, *testa* (f) head, *kara* (f) face, *olyo* (m) eye, *orela* (f) ear, *naso* (m) nose, *boka* (f) mouth, *dente* (m) tooth, *kore* (m) heart, *sangre* (m) blood, *pelo* (m) hair, *piel* (f) skin

**abstract** — *amor* (m) love, *vida* (f) life, *morte* (f) death, *istoria* (f) story, history, *kanto* (m) song, *musika* (f) music, *sonyo* (m) dream, *idea* (f) idea, *verita* (f) truth, *fuersa* (f) strength, force, *paz* (f) peace, *gera* (f) war, *travalyo* (m) work, *joko* (m) game, *festa* (f) party, feast, *viaje* (m) trip, voyage, *alegria* (f) joy, *pena* (f) sorrow, pain, *miedo* (m) fear, *esperansa* (f) hope, *razon* (f) reason, *kolor* (m) color, *poder* (m) power, *lei* (f) law

**time** — *tempo* (m) time, weather, *jorno* (m) day, *noche* (f) night, *manyana* (f) morning, tomorrow, *tarda* (f) afternoon, evening, *semana* (f) week, *mese* (m) month, *anyo* (m) year, *ora* (f) hour, *momento* (m) moment, *vez* (f) time, occasion


### Adjectives

*grande* big, *peti* small, *bon* good, *mal* bad, *belo* beautiful, *feo* ugly, *novo* new, *vielo* old, *joven* young, *alto* tall, high, *baso* low, short, *longo* long, *korto* short, *kaldo* hot, warm, *frido* cold, *klaro* clear, bright, *skuro* dark, *forte* strong, *debil* weak, *dulse* sweet, *amaro* bitter, *rapide* fast, *lento* slow, *felis* happy, *triste* sad, *rico* rich, *povre* poor, *vero* true, *falso* false, *pleno* full, *voide* empty, *fasil* easy, *difisil* difficult, *importante* important, *sabio* wise, *kontento* glad, content, *kansado* tired, *malade* sick, *sano* healthy, *limpio* clean, *susio* dirty, *seko* dry, *umido* wet, humid, *duro* hard, tough, *molle* soft, *pesante* heavy, *lejero* light (weight), *profondo* deep, *libre* free, *famozo* famous, *rojo* red, *verde* green, *blu* blue, *jalne* yellow, *blanko* white, *negro* black, *gris* gray, *brun* brown, *roza* pink, *dorado* golden


### Verbs

*kantar* sing, *parlar* speak, talk, *amar* love, *odiar* hate, *mirar* look at, watch, *vider* see, *audir* hear, listen, *komer* eat, *bever* drink, *dormir* sleep, *viver* live, *morir* die, *venir* come, *andar* walk, go, *currer* run, *volar* fly, *nadar* swim, *saltar* jump, *donar* give, *prender* take, grab, *portar* carry, bring, wear, *lasar* leave, let, *trovar* find, *buskar* look for, seek, *perder* lose, *gardar* keep, guard, *komprar* buy, *vender* sell, *pagar* pay, *fazer* do, make, *krear* create, *konstruir* build, *abrir* open, *serar* close, *komensar* begin, start, *finir* finish, end, *lezer* read, *skriver* write, *kontar* tell, count, *demandar* ask, *responder* answer, reply, *dizer* say, tell, *pensar* think, *kreder* believe, *saber* know (facts), *konoser* know, be acquainted, *aprender* learn, *ensenyar* teach, *studiar* study, *komprender* understand, *esperar* hope, wait for, *sentir* feel, *plorar* cry, weep, *jugar* play, *travalyar* work, *deskansar* rest, *aidar* help, *bailar* dance, *viajar* travel, *arivar* arrive, *partir* leave, depart, *tornar* return, *entrar* enter, *salir* go out, exit, *kader* fall, *tokar* touch, play, *mostrar* show, *kambiar* change, *kreser* grow, *brilar* shine, *sonar* sound, ring, *lavar* wash, *kosinar* cook, *kortar* cut, *plantar* plant

Modal/auxiliary-like: *poder* can, be able, *dever* must, should, *volir* want


### Prepositions

*de* of, from, *a* to, *en* in, at, *kon* with, *sin* without, *por* for, by, *pra* for (purpose), *sur* on, *sot* under, *entre* between, *ver* toward, *depos* after, *avan* before, *kontra* against, *asta* until


### Conjunctions

*e* and, *o* or, *ma* but, *ke* that, than, *si* if, *porke* because, *kuando* when, *kar* for, since, *donk* so, therefore, *mentre* while, *aunke* although


### Question words

*ke* what, *ki* who, *onde* where, *kuando* when, *komo* how, *porke* why, *kuanto* how much/many, *kual* which


### Adverbs & particles

*bien* well, *mal* badly, *muy* very, *mucho* a lot, *poko* little, *tro* too much, *asé* enough, *tanben* also, *sempre* always, *nunka* never, *ja* already, *ankor* still, yet, *aki* here, *ala* there, *oy* today, *yer* yesterday, *deman* tomorrow, *agora* now, *pos* then, *kasi* almost, *solo* only, *junto* together, *asi* thus, so, *nada* nothing, *tan* so (much)


### Numerals

0=*zero*, 1=*un*, 2=*du*, 3=*tre*, 4=*katr*, 5=*sink*, 6=*sis*, 7=*set*, 8=*ot*, 9=*nov*, 10=*dis*, 11=*onze*, 15=*kinze*, 20=*vint*, 30=*trenta*, 40=*karanta*, 50=*sinkanta*, 100=*sento*, 1000=*mil*


### Fixed phrases

*salú* — hi, hello, *bon jorno* — good day, good morning, *bona tarda* — good afternoon, *bona noche* — good night, *komo estas* — how are you, *ke tal* — how's it going, *yo so bien* — I am well, *muy bien, grasi* — very well, thanks, *e tu* — and you, *grasi* — thank you, *mersi mucho* — thanks a lot, *de nada* — you're welcome, *por favor* — please, *perdon* — sorry, excuse me, *no ai problema* — no problem, *asta manyana* — see you tomorrow, *asta pronto* — see you soon, *adiu* — goodbye, *bon viaje* — have a good trip, *felis anyo* — happy year

