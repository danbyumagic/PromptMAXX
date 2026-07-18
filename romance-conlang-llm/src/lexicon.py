"""
lexicon.py — the Solira dictionary.

Every entry carries an English gloss (used to auto-generate the dictionary in
LANGUAGE.md) and light semantic tags so the corpus generator can build
plausible sentences instead of merely grammatical ones.

Orthography note: Solira is written phonemically with a tight alphabet
(a b d e f g i j k l m n o p r s t u v y z, digraphs ch/ny/ly, and the two
accented interjection vowels é/ú). No c/q/w/x/h-outside-ch.
"""

# Semantic classes for nouns.
#   human  animal  thing  place  nature  food  body  abstract  time
# Verbs and adjectives reference these to pick sensible arguments.

# ---------------------------------------------------------------------------
# NOUNS: (word, gender, class, gloss)
# ---------------------------------------------------------------------------
NOUNS = [
    # -- humans --
    ("ome", "m", "human", "man"),
    ("fema", "f", "human", "woman"),
    ("enfant", "m", "human", "child"),
    ("amiko", "m", "human", "friend (m)"),
    ("amika", "f", "human", "friend (f)"),
    ("padre", "m", "human", "father"),
    ("madre", "f", "human", "mother"),
    ("fijo", "m", "human", "son"),
    ("fija", "f", "human", "daughter"),
    ("frate", "m", "human", "brother"),
    ("sore", "f", "human", "sister"),
    ("rey", "m", "human", "king"),
    ("reina", "f", "human", "queen"),
    ("mestre", "m", "human", "teacher"),
    ("studen", "m", "human", "student"),
    ("doktor", "m", "human", "doctor"),
    ("vesin", "m", "human", "neighbor"),
    ("poeta", "m", "human", "poet"),
    ("jente", "f", "human", "people, folk"),
    # -- animals --
    ("gato", "m", "animal", "cat"),
    ("kan", "m", "animal", "dog"),
    ("kavalo", "m", "animal", "horse"),
    ("ave", "f", "animal", "bird"),
    ("pese", "m", "animal", "fish"),
    ("leon", "m", "animal", "lion"),
    ("lobo", "m", "animal", "wolf"),
    ("oso", "m", "animal", "bear"),
    ("vaka", "f", "animal", "cow"),
    ("ovela", "f", "animal", "sheep"),
    ("abela", "f", "animal", "bee"),
    ("mariposa", "f", "animal", "butterfly"),
    # -- nature --
    ("sol", "m", "nature", "sun"),
    ("luna", "f", "nature", "moon"),
    ("strela", "f", "nature", "star"),
    ("sielo", "m", "nature", "sky"),
    ("mar", "m", "nature", "sea"),
    ("tera", "f", "nature", "earth, land"),
    ("mundo", "m", "nature", "world"),
    ("montanya", "f", "nature", "mountain"),
    ("rio", "m", "nature", "river"),
    ("lago", "m", "nature", "lake"),
    ("foresta", "f", "nature", "forest"),
    ("arbre", "m", "nature", "tree"),
    ("flor", "f", "nature", "flower"),
    ("folya", "f", "nature", "leaf"),
    ("erba", "f", "nature", "grass"),
    ("piedra", "f", "nature", "stone"),
    ("fuego", "m", "nature", "fire"),
    ("agua", "f", "nature", "water"),
    ("vento", "m", "nature", "wind"),
    ("ploja", "f", "nature", "rain"),
    ("neve", "f", "nature", "snow"),
    ("nube", "f", "nature", "cloud"),
    ("luz", "f", "nature", "light"),
    # -- places --
    ("kasa", "f", "place", "house"),
    ("sivda", "f", "place", "city"),
    ("pais", "m", "place", "country"),
    ("strada", "f", "place", "street, road"),
    ("kamin", "m", "place", "path, way"),
    ("plaza", "f", "place", "square"),
    ("mercato", "m", "place", "market"),
    ("skola", "f", "place", "school"),
    ("jardin", "m", "place", "garden"),
    ("kampo", "m", "place", "field, countryside"),
    ("porta", "f", "place", "door"),
    ("fenetra", "f", "place", "window"),
    ("tabla", "f", "place", "table"),
    ("sila", "f", "place", "chair"),
    ("leto", "m", "place", "bed"),
    ("muro", "m", "place", "wall"),
    ("palas", "m", "place", "palace"),
    ("tore", "f", "place", "tower"),
    ("ponte", "m", "place", "bridge"),
    # -- things --
    ("libro", "m", "thing", "book"),
    ("palabra", "f", "thing", "word"),
    ("lingua", "f", "thing", "language, tongue"),
    ("nome", "m", "thing", "name"),
    ("letra", "f", "thing", "letter"),
    ("papel", "m", "thing", "paper"),
    ("plume", "f", "thing", "pen, feather"),
    ("kopa", "f", "thing", "cup"),
    ("plato", "m", "thing", "plate, dish"),
    ("moneda", "f", "thing", "coin, money"),
    ("oro", "m", "thing", "gold"),
    ("fero", "m", "thing", "iron"),
    ("ropa", "f", "thing", "clothes"),
    ("sapato", "m", "thing", "shoe"),
    ("chapel", "m", "thing", "hat"),
    ("klave", "f", "thing", "key"),
    ("barka", "f", "thing", "boat"),
    ("nave", "f", "thing", "ship"),
    ("karo", "m", "thing", "car, cart"),
    ("tren", "m", "thing", "train"),
    ("makina", "f", "thing", "machine"),
    ("telefon", "m", "thing", "telephone"),
    # -- food --
    ("pan", "m", "food", "bread"),
    ("vino", "m", "food", "wine"),
    ("kafe", "m", "food", "coffee"),
    ("lete", "m", "food", "milk"),
    ("fruta", "f", "food", "fruit"),
    ("pomo", "m", "food", "apple"),
    ("keso", "m", "food", "cheese"),
    ("sukro", "m", "food", "sugar"),
    ("sal", "m", "food", "salt"),
    ("karne", "f", "food", "meat"),
    ("sopa", "f", "food", "soup"),
    # -- body --
    ("man", "f", "body", "hand"),
    ("brase", "m", "body", "arm"),
    ("pede", "m", "body", "foot"),
    ("gamba", "f", "body", "leg"),
    ("testa", "f", "body", "head"),
    ("kara", "f", "body", "face"),
    ("olyo", "m", "body", "eye"),
    ("orela", "f", "body", "ear"),
    ("naso", "m", "body", "nose"),
    ("boka", "f", "body", "mouth"),
    ("dente", "m", "body", "tooth"),
    ("kore", "m", "body", "heart"),
    ("sangre", "m", "body", "blood"),
    ("pelo", "m", "body", "hair"),
    ("piel", "f", "body", "skin"),
    # -- abstract --
    ("amor", "m", "abstract", "love"),
    ("vida", "f", "abstract", "life"),
    ("morte", "f", "abstract", "death"),
    ("istoria", "f", "abstract", "story, history"),
    ("kanto", "m", "abstract", "song"),
    ("musika", "f", "abstract", "music"),
    ("sonyo", "m", "abstract", "dream"),
    ("idea", "f", "abstract", "idea"),
    ("verita", "f", "abstract", "truth"),
    ("fuersa", "f", "abstract", "strength, force"),
    ("paz", "f", "abstract", "peace"),
    ("gera", "f", "abstract", "war"),
    ("travalyo", "m", "abstract", "work"),
    ("joko", "m", "abstract", "game"),
    ("festa", "f", "abstract", "party, feast"),
    ("viaje", "m", "abstract", "trip, voyage"),
    ("alegria", "f", "abstract", "joy"),
    ("pena", "f", "abstract", "sorrow, pain"),
    ("miedo", "m", "abstract", "fear"),
    ("esperansa", "f", "abstract", "hope"),
    ("razon", "f", "abstract", "reason"),
    ("kolor", "m", "abstract", "color"),
    ("poder", "m", "abstract", "power"),
    ("lei", "f", "abstract", "law"),
    # -- time --
    ("tempo", "m", "time", "time, weather"),
    ("jorno", "m", "time", "day"),
    ("noche", "f", "time", "night"),
    ("manyana", "f", "time", "morning, tomorrow"),
    ("tarda", "f", "time", "afternoon, evening"),
    ("semana", "f", "time", "week"),
    ("mese", "m", "time", "month"),
    ("anyo", "m", "time", "year"),
    ("ora", "f", "time", "hour"),
    ("momento", "m", "time", "moment"),
    ("vez", "f", "time", "time, occasion"),
]

# ---------------------------------------------------------------------------
# ADJECTIVES: (word, applicable_classes, gloss)
#   "any" applies to every class. Adjectives ending in -o/-a inflect for
#   gender; the rest are gender-invariant (see morphology.agree_adj).
# ---------------------------------------------------------------------------
ADJECTIVES = [
    ("grande", ["any"], "big"),
    ("peti", ["any"], "small"),
    ("bon", ["any"], "good"),
    ("mal", ["any"], "bad"),
    ("belo", ["human", "animal", "thing", "nature", "place"], "beautiful"),
    ("feo", ["human", "animal", "thing"], "ugly"),
    ("novo", ["thing", "abstract", "place"], "new"),
    ("vielo", ["human", "animal", "thing", "place"], "old"),
    ("joven", ["human", "animal"], "young"),
    ("alto", ["human", "thing", "place", "nature"], "tall, high"),
    ("baso", ["human", "thing", "place"], "low, short"),
    ("longo", ["thing", "place", "abstract"], "long"),
    ("korto", ["thing", "abstract"], "short"),
    ("kaldo", ["thing", "nature", "food", "time"], "hot, warm"),
    ("frido", ["thing", "nature", "food", "time"], "cold"),
    ("klaro", ["any"], "clear, bright"),
    ("skuro", ["thing", "nature", "place", "time"], "dark"),
    ("forte", ["human", "animal", "thing", "abstract"], "strong"),
    ("debil", ["human", "animal", "abstract"], "weak"),
    ("dulse", ["food", "abstract"], "sweet"),
    ("amaro", ["food"], "bitter"),
    ("rapide", ["human", "animal", "thing"], "fast"),
    ("lento", ["human", "animal", "thing"], "slow"),
    ("felis", ["human", "animal"], "happy"),
    ("triste", ["human", "abstract"], "sad"),
    ("rico", ["human", "place"], "rich"),
    ("povre", ["human", "place"], "poor"),
    ("vero", ["abstract"], "true"),
    ("falso", ["abstract"], "false"),
    ("pleno", ["thing", "place"], "full"),
    ("voide", ["thing", "place"], "empty"),
    ("fasil", ["abstract"], "easy"),
    ("difisil", ["abstract"], "difficult"),
    ("importante", ["abstract", "human", "thing"], "important"),
    ("sabio", ["human"], "wise"),
    ("kontento", ["human"], "glad, content"),
    ("kansado", ["human", "animal"], "tired"),
    ("malade", ["human", "animal"], "sick"),
    ("sano", ["human", "animal"], "healthy"),
    ("limpio", ["thing", "place", "body"], "clean"),
    ("susio", ["thing", "place", "body"], "dirty"),
    ("seko", ["thing", "nature", "food"], "dry"),
    ("umido", ["thing", "nature", "time"], "wet, humid"),
    ("duro", ["thing", "food", "abstract"], "hard, tough"),
    ("molle", ["thing", "food"], "soft"),
    ("pesante", ["thing"], "heavy"),
    ("lejero", ["thing"], "light (weight)"),
    ("profondo", ["thing", "nature", "abstract"], "deep"),
    ("libre", ["human", "abstract"], "free"),
    ("famozo", ["human", "place", "thing"], "famous"),
    # -- colors (apply to concrete things) --
    ("rojo", ["thing", "nature", "animal", "food", "body"], "red"),
    ("verde", ["thing", "nature", "food"], "green"),
    ("blu", ["thing", "nature"], "blue"),
    ("jalne", ["thing", "nature", "food"], "yellow"),
    ("blanko", ["thing", "nature", "animal", "body"], "white"),
    ("negro", ["thing", "nature", "animal", "body"], "black"),
    ("gris", ["thing", "nature", "animal"], "gray"),
    ("brun", ["thing", "nature", "animal", "body"], "brown"),
    ("roza", ["thing", "nature"], "pink"),
    ("dorado", ["thing", "nature"], "golden"),
]

# ---------------------------------------------------------------------------
# VERBS: (infinitive, frame, gloss)
#   frame is one of:
#     ("intr", subj)                  intransitive
#     ("tr", subj, [obj_classes])     transitive, object drawn from classes
#     ("modal",)                      takes a following infinitive
#     ("comp",  subj)                 takes a "ke ..." clause (think/believe)
#     ("cop_loc", subj)               motion/location, takes a place phrase
#   subj is one of: human, animate (human|animal), any
# ---------------------------------------------------------------------------
VERBS = [
    ("kantar", ("tr", "human", ["abstract"]), "sing"),
    ("parlar", ("intr", "human"), "speak, talk"),
    ("amar", ("tr", "human", ["human", "animal", "abstract", "thing", "nature"]), "love"),
    ("odiar", ("tr", "human", ["human", "abstract", "thing"]), "hate"),
    ("mirar", ("tr", "human", ["any"]), "look at, watch"),
    ("vider", ("tr", "human", ["any"]), "see"),
    ("audir", ("tr", "human", ["abstract", "nature"]), "hear, listen"),
    ("komer", ("tr", "animate", ["food"]), "eat"),
    ("bever", ("tr", "animate", ["food", "nature"]), "drink"),
    ("dormir", ("intr", "animate"), "sleep"),
    ("viver", ("cop_loc", "animate"), "live"),
    ("morir", ("intr", "animate"), "die"),
    ("venir", ("cop_loc", "animate"), "come"),
    ("andar", ("cop_loc", "animate"), "walk, go"),
    ("currer", ("intr", "animate"), "run"),
    ("volar", ("intr", "animate"), "fly"),
    ("nadar", ("intr", "animate"), "swim"),
    ("saltar", ("intr", "animate"), "jump"),
    ("donar", ("tr", "human", ["thing", "food", "abstract"]), "give"),
    ("prender", ("tr", "human", ["thing", "food"]), "take, grab"),
    ("portar", ("tr", "human", ["thing", "food"]), "carry, bring, wear"),
    ("lasar", ("tr", "human", ["thing", "place", "human"]), "leave, let"),
    ("trovar", ("tr", "human", ["any"]), "find"),
    ("buskar", ("tr", "human", ["any"]), "look for, seek"),
    ("perder", ("tr", "human", ["thing", "abstract"]), "lose"),
    ("gardar", ("tr", "human", ["thing", "abstract"]), "keep, guard"),
    ("komprar", ("tr", "human", ["thing", "food"]), "buy"),
    ("vender", ("tr", "human", ["thing", "food"]), "sell"),
    ("pagar", ("tr", "human", ["thing"]), "pay"),
    ("fazer", ("tr", "human", ["thing", "abstract"]), "do, make"),
    ("krear", ("tr", "human", ["thing", "abstract"]), "create"),
    ("konstruir", ("tr", "human", ["place", "thing"]), "build"),
    ("abrir", ("tr", "human", ["thing", "place", "body"]), "open"),
    ("serar", ("tr", "human", ["thing", "place", "body"]), "close"),
    ("komensar", ("tr", "human", ["abstract"]), "begin, start"),
    ("finir", ("tr", "human", ["abstract"]), "finish, end"),
    ("lezer", ("tr", "human", ["thing", "abstract"]), "read"),
    ("skriver", ("tr", "human", ["thing", "abstract"]), "write"),
    ("kontar", ("tr", "human", ["abstract"]), "tell, count"),
    ("demandar", ("tr", "human", ["abstract"]), "ask"),
    ("responder", ("intr", "human"), "answer, reply"),
    ("dizer", ("tr", "human", ["abstract"]), "say, tell"),
    ("pensar", ("comp", "human"), "think"),
    ("kreder", ("comp", "human"), "believe"),
    ("saber", ("tr", "human", ["abstract", "thing"]), "know (facts)"),
    ("konoser", ("tr", "human", ["human", "place"]), "know, be acquainted"),
    ("aprender", ("tr", "human", ["abstract", "thing"]), "learn"),
    ("ensenyar", ("tr", "human", ["abstract", "thing"]), "teach"),
    ("studiar", ("tr", "human", ["abstract", "thing"]), "study"),
    ("komprender", ("tr", "human", ["abstract"]), "understand"),
    ("esperar", ("tr", "human", ["abstract"]), "hope, wait for"),
    ("sentir", ("tr", "human", ["abstract"]), "feel"),
    ("plorar", ("intr", "human"), "cry, weep"),
    ("jugar", ("intr", "human"), "play"),
    ("travalyar", ("intr", "human"), "work"),
    ("deskansar", ("intr", "human"), "rest"),
    ("aidar", ("tr", "human", ["human"]), "help"),
    ("bailar", ("intr", "human"), "dance"),
    ("viajar", ("intr", "human"), "travel"),
    ("arivar", ("cop_loc", "animate"), "arrive"),
    ("partir", ("intr", "animate"), "leave, depart"),
    ("tornar", ("cop_loc", "animate"), "return"),
    ("entrar", ("cop_loc", "animate"), "enter"),
    ("salir", ("intr", "animate"), "go out, exit"),
    ("kader", ("intr", "any"), "fall"),
    ("tokar", ("tr", "human", ["thing", "abstract", "body"]), "touch, play"),
    ("mostrar", ("tr", "human", ["thing", "abstract"]), "show"),
    ("kambiar", ("tr", "human", ["thing", "abstract"]), "change"),
    ("kreser", ("intr", "any"), "grow"),
    ("brilar", ("intr", "nature"), "shine"),
    ("sonar", ("intr", "thing"), "sound, ring"),
    ("lavar", ("tr", "human", ["thing", "body"]), "wash"),
    ("kosinar", ("tr", "human", ["food"]), "cook"),
    ("kortar", ("tr", "human", ["thing", "food"]), "cut"),
    ("plantar", ("tr", "human", ["nature"]), "plant"),
]

# Verbs that read naturally after a modal or in the future (infinitive slot).
MODAL_VERBS = ["poder", "dever", "volir"]      # can / must / want
MODAL_GLOSS = {"poder": "can, be able", "dever": "must, should", "volir": "want"}

# ---------------------------------------------------------------------------
# Function words
# ---------------------------------------------------------------------------
PREPOSITIONS = {
    "de": "of, from", "a": "to", "en": "in, at", "kon": "with",
    "sin": "without", "por": "for, by", "pra": "for (purpose)",
    "sur": "on", "sot": "under", "entre": "between", "ver": "toward",
    "depos": "after", "avan": "before", "kontra": "against", "asta": "until",
}
PLACE_PREPS = ["en", "a", "ver", "de", "sur", "sot"]

CONJUNCTIONS = {
    "e": "and", "o": "or", "ma": "but", "ke": "that, than", "si": "if",
    "porke": "because", "kuando": "when", "kar": "for, since",
    "donk": "so, therefore", "mentre": "while", "aunke": "although",
}

QUESTION_WORDS = {
    "ke": "what", "ki": "who", "onde": "where", "kuando": "when",
    "komo": "how", "porke": "why", "kuanto": "how much/many", "kual": "which",
}

ADVERBS = {
    "bien": "well", "mal": "badly", "muy": "very", "mucho": "a lot",
    "poko": "little", "tro": "too much", "asé": "enough", "tanben": "also",
    "sempre": "always", "nunka": "never", "ja": "already", "ankor": "still, yet",
    "aki": "here", "ala": "there", "oy": "today", "yer": "yesterday",
    "deman": "tomorrow", "agora": "now", "pos": "then", "kasi": "almost",
    "solo": "only", "junto": "together", "asi": "thus, so", "nada": "nothing",
    "tan": "so (much)",
}

# Interjections / discourse particles used in set phrases.
INTERJECTIONS = {
    "ola": "hi, hello", "salú": "hi", "adiu": "goodbye", "si": "yes",
    "no": "no", "grasi": "thanks", "mersi": "thanks", "perdon": "sorry",
}

# Cardinal numerals 0..20 plus the tens and hundreds used by number_word().
NUMERALS = {
    0: "zero", 1: "un", 2: "du", 3: "tre", 4: "katr", 5: "sink",
    6: "sis", 7: "set", 8: "ot", 9: "nov", 10: "dis",
    11: "onze", 12: "doze", 13: "treze", 14: "katorze", 15: "kinze",
    16: "dissis", 17: "disset", 18: "disot", 19: "disnov", 20: "vint",
    30: "trenta", 40: "karanta", 50: "sinkanta", 60: "sesanta",
    70: "setanta", 80: "otanta", 90: "novanta", 100: "sento", 1000: "mil",
}

# Fixed conversational phrases (English gloss) for the greetings genre.
PHRASES = [
    ("salú", "hi, hello"),
    ("bon jorno", "good day, good morning"),
    ("bona tarda", "good afternoon"),
    ("bona noche", "good night"),
    ("komo estas", "how are you"),
    ("ke tal", "how's it going"),
    ("yo so bien", "I am well"),
    ("muy bien, grasi", "very well, thanks"),
    ("e tu", "and you"),
    ("grasi", "thank you"),
    ("mersi mucho", "thanks a lot"),
    ("de nada", "you're welcome"),
    ("por favor", "please"),
    ("perdon", "sorry, excuse me"),
    ("no ai problema", "no problem"),
    ("asta manyana", "see you tomorrow"),
    ("asta pronto", "see you soon"),
    ("adiu", "goodbye"),
    ("bon viaje", "have a good trip"),
    ("felis anyo", "happy year"),
]


def number_word(n: int) -> str:
    """Spell a non-negative integer 0..999 in Solira."""
    if n in NUMERALS:
        return NUMERALS[n]
    if n < 100:
        tens, ones = (n // 10) * 10, n % 10
        return f"{NUMERALS[tens]}-{NUMERALS[ones]}"
    hundreds, rest = n // 100, n % 100
    head = NUMERALS[100] if hundreds == 1 else f"{NUMERALS[hundreds]} {NUMERALS[100]}"
    if rest == 0:
        return head
    return f"{head} {number_word(rest)}"


# Convenience indexes built once at import.
NOUNS_BY_CLASS = {}
for _w, _g, _c, _gl in NOUNS:
    NOUNS_BY_CLASS.setdefault(_c, []).append((_w, _g))

ALL_CLASSES = list(NOUNS_BY_CLASS.keys())


def adjectives_for(noun_class: str):
    """Adjectives that can sensibly describe a noun of the given class."""
    out = []
    for w, classes, _ in ADJECTIVES:
        if "any" in classes or noun_class in classes:
            out.append(w)
    return out


if __name__ == "__main__":
    print(f"{len(NOUNS)} nouns, {len(ADJECTIVES)} adjectives, {len(VERBS)} verbs")
    print("classes:", ALL_CLASSES)
    print("numbers:", [number_word(n) for n in (7, 15, 23, 40, 99, 100, 234)])
