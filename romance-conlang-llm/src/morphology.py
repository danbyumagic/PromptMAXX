"""
morphology.py — the inflectional engine for Solira.

Solira is a constructed Romance language (see LANGUAGE.md). Its grammar is
deliberately *regular*: almost every word inflects by rule, with only a
handful of high-frequency auxiliaries/copulas stored as explicit tables.
That regularity is what lets a ~1M parameter model learn to speak it.

This module turns dictionary (citation) forms into inflected forms:
    - verbs:  conjugate() for present, participle, gerund, imperative
    - nouns:  pluralize()
    - adjs:   agree_adj()   (gender + number agreement)
    - articles / possessives / demonstratives by gender & number

Person indices used throughout:  0=yo 1=tu 2=el/ela 3=noi 4=voi 5=eli
"""

VOWELS = set("aeiouáéíóúàèìòù")

# ---------------------------------------------------------------------------
# Verbs
# ---------------------------------------------------------------------------

# Theme vowel selected by the infinitive class (-ar / -er / -ir).
_THEME = {"ar": "a", "er": "e", "ir": "i"}

# The four irregular verbs. Only the present indicative is irregular; their
# non-finite forms (participle/gerund) are given explicitly too.
IRREGULAR = {
    # eser — "to be" (identity / essence, like Spanish ser).
    # 2sg and 3sg share "es"; pro-drop context disambiguates.
    "eser": {
        "pres": ["so", "es", "es", "somos", "sotz", "son"],
        "imp": ["era", "eras", "era", "eramos", "eratz", "eran"],
        "part": "sit", "ger": "sendo",
    },
    # star — "to be" (state / location, like Spanish estar)
    "star": {
        "pres": ["sto", "stas", "sta", "stamos", "statz", "stan"],
        "imp": ["stava", "stavas", "stava", "stavamos", "stavatz", "stavan"],
        "part": "stat", "ger": "stando",
    },
    # avir — "to have" (also the past-tense auxiliary)
    "avir": {
        "pres": ["ai", "as", "a", "amos", "atz", "an"],
        "imp": ["avia", "avias", "avia", "aviamos", "aviatz", "avian"],
        "part": "avit", "ger": "avendo",
    },
    # var — "to go" (also the future auxiliary: va + infinitive)
    "var": {
        "pres": ["vo", "vas", "va", "vamos", "vatz", "van"],
        "imp": ["iva", "ivas", "iva", "ivamos", "ivatz", "ivan"],
        "part": "vat", "ger": "vando",
    },
}


def verb_class(inf: str) -> str:
    """Return the two-letter conjugation class of an infinitive."""
    return inf[-2:]


def stem(inf: str) -> str:
    return inf[:-2]


def theme(inf: str) -> str:
    return _THEME[verb_class(inf)]


def conjugate(inf: str, person: int) -> str:
    """Present indicative form of `inf` for the given person (0..5)."""
    if inf in IRREGULAR:
        return IRREGULAR[inf]["pres"][person]
    s, th = stem(inf), theme(inf)
    endings = ["o", th + "s", th, th + "mos", th + "tz", th + "n"]
    return s + endings[person]


def imperfect(inf: str, person: int) -> str:
    """Imperfect (past descriptive/habitual) form for the given person.

    Regular: stem + theme + 'va' + person marker, e.g. kantava, komeva.
    """
    if inf in IRREGULAR:
        return IRREGULAR[inf]["imp"][person]
    s, th = stem(inf), theme(inf)
    endings = ["va", "vas", "va", "vamos", "vatz", "van"]
    return s + th + endings[person]


def participle(inf: str) -> str:
    """Past participle (used with `avir` to form the past)."""
    if inf in IRREGULAR:
        return IRREGULAR[inf]["part"]
    return stem(inf) + theme(inf) + "t"


def gerund(inf: str) -> str:
    """Gerund / present participle (used with `star` for the progressive)."""
    if inf in IRREGULAR:
        return IRREGULAR[inf]["ger"]
    return stem(inf) + theme(inf) + "ndo"


def imperative(inf: str, plural: bool = False) -> str:
    """Imperative: tu-form (=3sg) or voi-form (=2pl)."""
    if inf in IRREGULAR:
        # irregular imperatives fall back to the 2sg/2pl present
        return IRREGULAR[inf]["pres"][4 if plural else 2]
    s, th = stem(inf), theme(inf)
    return s + th + ("tz" if plural else "")


# ---------------------------------------------------------------------------
# Nouns
# ---------------------------------------------------------------------------

def pluralize(word: str) -> str:
    """Regular plural: +s after a vowel, +es after a consonant."""
    if word[-1] in VOWELS:
        return word + "s"
    return word + "es"


# ---------------------------------------------------------------------------
# Adjectives
# ---------------------------------------------------------------------------

def agree_adj(adj: str, gender: str, number: str) -> str:
    """Inflect an adjective for gender ('m'/'f') and number ('s'/'p').

    Adjectives in -o/-a mark gender (o<->a). Everything else is
    gender-invariant. Plural follows the noun rule.
    """
    base = adj
    if adj.endswith("o") or adj.endswith("a"):
        base = adj[:-1] + ("a" if gender == "f" else "o")
    if number == "p":
        return pluralize(base)
    return base


# ---------------------------------------------------------------------------
# Determiners
# ---------------------------------------------------------------------------

def article(definite: bool, gender: str, number: str) -> str:
    """Definite: le/la/les.  Indefinite: un/una/unes."""
    if number == "p":
        return "les" if definite else "unes"
    if definite:
        return "le" if gender == "m" else "la"
    return "un" if gender == "m" else "una"


# Possessive determiners inflect only for number (like English), e.g. mi/mis.
_POSS = {
    0: "mi", 1: "tu", 2: "su", 3: "nos", 4: "vos", 5: "lor",
}


def possessive(person: int, number: str) -> str:
    base = _POSS[person]
    if number == "p" and base in ("mi", "tu", "su"):
        return base + "s"
    return base


# Demonstratives: este (this) / akel (that), agreeing in gender+number.
def demonstrative(distal: bool, gender: str, number: str) -> str:
    root = "akel" if distal else "est"
    if gender == "f":
        form = root + "a"
    else:
        form = root + ("e" if root == "est" else "")
    return pluralize(form) if number == "p" else form


# Subject and object pronoun tables (indexed by person 0..5).
SUBJECT_PRON = ["yo", "tu", "el", "noi", "voi", "eli"]
SUBJECT_PRON_F = {2: "ela", 5: "elas"}      # feminine variants
OBJECT_PRON = ["me", "te", "lo", "nos", "vos", "los"]
OBJECT_PRON_F = {2: "la", 5: "las"}


def subject_pronoun(person: int, gender: str = "m") -> str:
    if gender == "f" and person in SUBJECT_PRON_F:
        return SUBJECT_PRON_F[person]
    return SUBJECT_PRON[person]


def object_pronoun(person: int, gender: str = "m") -> str:
    if gender == "f" and person in OBJECT_PRON_F:
        return OBJECT_PRON_F[person]
    return OBJECT_PRON[person]


if __name__ == "__main__":
    # Tiny self-check when run directly.
    for inf in ["kantar", "komer", "dormir", "eser", "avir", "var"]:
        forms = [conjugate(inf, p) for p in range(6)]
        print(f"{inf:8} {forms}  part={participle(inf)} ger={gerund(inf)}")
    print("plural flor ->", pluralize("flor"), "| kasa ->", pluralize("kasa"))
    print("negro f.p ->", agree_adj("negro", "f", "p"))
