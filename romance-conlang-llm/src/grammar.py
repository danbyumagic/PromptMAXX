"""
grammar.py — a generative grammar for Solira.

Given the lexicon and morphology engine, this composes fully inflected,
agreement-correct sentences across many templates, then bundles them into
short documents by genre. Each document is prefixed with a genre tag so the
trained model can be steered at inference time:

    [FRASE]     one declarative sentence
    [DIALOG]    a short spoken exchange
    [HISTORIA]  a short narrative paragraph
    [SALU]      a greeting exchange
    [QA]        a question and its answer

The output is intentionally regular: the point is a corpus a ~1M parameter
model can actually generalise from.
"""
import random

import lexicon as lx
import morphology as mo

GENRE_TAGS = ["[FRASE]", "[DIALOG]", "[HISTORIA]", "[SALU]", "[QA]"]

_ANIMATE = ["human", "animal"]
_CONCRETE = ["human", "animal", "thing", "place", "nature", "food", "body"]
_LOC_PREPS = ["en", "sur", "sot", "a"]
# human "role" nouns usable as identity predicates ("she is a teacher")
_ROLES = [(w, g) for (w, g, c, gl) in lx.NOUNS
          if c == "human" and w != "jente"]


def cap(s: str) -> str:
    for i, ch in enumerate(s):
        if ch.isalpha():
            return s[:i] + ch.upper() + s[i + 1:]
    return s


class Gen:
    def __init__(self, seed=0):
        self.r = random.Random(seed)

    # -- primitive pickers ---------------------------------------------------
    def pick_noun(self, classes):
        if "any" in classes:
            classes = _CONCRETE
        pool = []
        for c in classes:
            pool.extend(lx.NOUNS_BY_CLASS.get(c, []))
        return self.r.choice(pool)  # (word, gender)

    def noun_class_of(self, word):
        for w, g, c, gl in lx.NOUNS:
            if w == word:
                return c
        return "thing"

    # -- noun phrases --------------------------------------------------------
    def noun_phrase(self, classes, number=None, definite=None,
                    p_adj=0.4, p_poss=0.15, p_num=0.15):
        """Return (text, gender, number, noun_class)."""
        word, gender = self.pick_noun(classes)
        ncls = self.noun_class_of(word)
        if number is None:
            number = "p" if self.r.random() < 0.28 else "s"

        head = mo.pluralize(word) if number == "p" else word

        # adjective (post-nominal, agreeing)
        adj_txt = ""
        if self.r.random() < p_adj:
            adjs = lx.adjectives_for(ncls)
            if adjs:
                adj = self.r.choice(adjs)
                adj_txt = " " + mo.agree_adj(adj, gender, number)

        # determiner: number word, possessive, or article
        roll = self.r.random()
        if number == "p" and roll < p_num:
            n = self.r.choice([2, 2, 3, 3, 4, 5, 6, 7, 10])
            det = lx.number_word(n)
            return f"{det} {head}{adj_txt}", gender, number, ncls
        if roll < p_num + p_poss:
            det = mo.possessive(self.r.randint(0, 5), number)
            return f"{det} {head}{adj_txt}", gender, number, ncls

        if definite is None:
            definite = self.r.random() < 0.6
        art = mo.article(definite, gender, number)
        return f"{art} {head}{adj_txt}", gender, number, ncls

    def place_phrase(self):
        prep = self.r.choice(lx.PLACE_PREPS)
        txt, *_ = self.noun_phrase(["place", "nature", "place"], p_adj=0.3,
                                   p_num=0.0, p_poss=0.1)
        return f"{prep} {txt}"

    def locative_phrase(self):
        """A static location (for existentials): en/sur/sot/a + place."""
        prep = self.r.choice(_LOC_PREPS)
        txt, *_ = self.noun_phrase(["place", "nature"], number="s",
                                   p_adj=0.3, p_num=0.0, p_poss=0.1)
        return f"{prep} {txt}"

    def role_phrase(self, number):
        """An indefinite human-role NP: 'un mestre', 'unes doktores'."""
        word, gender = self.r.choice(_ROLES)
        head = mo.pluralize(word) if number == "p" else word
        adj = ""
        if self.r.random() < 0.3:
            adj = " " + mo.agree_adj(self.r.choice(lx.adjectives_for("human")),
                                     gender, number)
        return f"{mo.article(False, gender, number)} {head}{adj}"

    # -- subjects ------------------------------------------------------------
    def subject(self, kind):
        """Return dict(text, person, gender, ncls, dropped)."""
        # ~35% pronoun subject, otherwise a full NP
        if self.r.random() < 0.35:
            person = self.r.randint(0, 5)
            gender = self.r.choice(["m", "f"])
            drop = self.r.random() < 0.45  # pro-drop
            txt = "" if drop else mo.subject_pronoun(person, gender)
            return dict(text=txt, person=person, gender=gender,
                        ncls="human", dropped=drop)
        classes = {"human": ["human"], "animate": _ANIMATE,
                   "any": _CONCRETE, "nature": ["nature"],
                   "thing": ["thing", "abstract"]}.get(kind, ["human"])
        txt, gender, number, ncls = self.noun_phrase(classes, p_num=0.12)
        person = 5 if number == "p" else 2
        return dict(text=txt, person=person, gender=gender, ncls=ncls,
                    dropped=False)

    def _svo_prefix(self, subj):
        return "" if subj["dropped"] else subj["text"] + " "

    # -- verb phrases by tense ----------------------------------------------
    def verb_phrase(self, verb, subj, tense):
        inf, frame, _ = verb
        person = subj["person"]

        if tense == "pres":
            head = mo.conjugate(inf, person)
        elif tense == "imp":
            head = mo.imperfect(inf, person)
        elif tense == "past":
            head = f"{mo.conjugate('avir', person)} {mo.participle(inf)}"
        elif tense == "fut":
            head = f"{mo.conjugate('var', person)} {inf}"
        elif tense == "prog":
            head = f"{mo.conjugate('star', person)} {mo.gerund(inf)}"
        else:
            head = mo.conjugate(inf, person)

        obj = self._complement(frame)
        return f"{head}{obj}"

    def _complement(self, frame):
        kind = frame[0]
        if kind == "tr":
            txt, *_ = self.noun_phrase(frame[2])
            return " " + txt
        if kind == "cop_loc":
            if self.r.random() < 0.85:
                return " " + self.place_phrase()
            return ""
        if kind == "comp":
            return " ke " + self.declarative_core(sub=True)
        return ""  # intransitive

    # -- whole declaratives --------------------------------------------------
    def declarative_core(self, sub=False):
        """A subject+predicate clause without terminal punctuation."""
        style = self.r.random()
        if style < 0.22:
            return self._copular()
        if style < 0.34:
            return self._existential()
        if style < 0.46:
            return self._modal()
        # plain SVO in one of several tenses
        verb = self.r.choice(lx.VERBS)
        subj = self.subject(verb[1][1] if verb[1][0] != "modal" else "human")
        tense = self.r.choices(["pres", "past", "fut", "prog", "imp"],
                               weights=[5, 3, 2, 2, 2])[0]
        neg = "no " if self.r.random() < 0.12 else ""
        vp = self.verb_phrase(verb, subj, tense)
        clause = f"{self._svo_prefix(subj)}{neg}{vp}".strip()
        # optional trailing adverbial
        if not sub and self.r.random() < 0.22:
            clause += " " + self.r.choice(
                ["oy", "deman", "yer", "agora", "sempre", "aki", "ala",
                 "bien", "junto", "kon alegria"])
        return clause

    def _copular(self):
        subj = self.subject("any")
        gender = subj["gender"]
        number = "p" if subj["person"] == 5 else "s"
        if self.r.random() < 0.6:  # predicate adjective
            adjs = lx.adjectives_for(subj["ncls"])
            adj = mo.agree_adj(self.r.choice(adjs), gender, number)
            cop = mo.conjugate("eser", subj["person"])
            neg = "no " if self.r.random() < 0.1 else ""
            return f"{self._svo_prefix(subj)}{neg}{cop} {adj}".strip()
        # predicate nominal (identity)  OR  location with star
        if self.r.random() < 0.5:
            cop = mo.conjugate("eser", subj["person"])
            return f"{self._svo_prefix(subj)}{cop} {self.role_phrase(number)}".strip()
        star = mo.conjugate("star", subj["person"])
        return f"{self._svo_prefix(subj)}{star} {self.locative_phrase()}".strip()

    def _existential(self):
        np, g, number, ncls = self.noun_phrase(
            _CONCRETE, definite=False, p_num=0.5, p_adj=0.4)
        if self.r.random() < 0.5:
            return f"ai {np} {self.locative_phrase()}"
        return f"{self.locative_phrase()} ai {np}"

    def _modal(self):
        modal = self.r.choice(lx.MODAL_VERBS)
        subj = self.subject("human")
        main = self.r.choice([v for v in lx.VERBS if v[1][0] in ("tr", "intr", "cop_loc")])
        neg = "no " if self.r.random() < 0.12 else ""
        m = mo.conjugate(modal, subj["person"])
        comp = self._complement(main[1])
        return f"{self._svo_prefix(subj)}{neg}{m} {main[0]}{comp}".strip()

    def declarative(self):
        return cap(self.declarative_core()) + self.r.choice([".", ".", ".", "!"])

    # -- questions & answers -------------------------------------------------
    def question(self):
        qtype = self.r.random()
        if qtype < 0.45:  # yes/no
            core = self.declarative_core()
            q = f"esk {core}?"
            ans = self._short_answer()
            return cap(q), ans
        # wh-question
        qw = self.r.choice(["onde", "ki", "kuanto", "komo", "porke", "ke"])
        if qw == "onde":
            subj, gender, _, _ = self.noun_phrase(_CONCRETE, number="s", p_num=0.0)
            q = f"onde sta {subj}?"
            ans = cap(f"{subj} sta {self.locative_phrase()}") + "."
        elif qw == "ki":
            q = "ki es akela person?"
            ans = cap(f"akela person es {self.role_phrase('s')}") + "."
        elif qw == "kuanto":
            word, gender = self.pick_noun(_CONCRETE)
            plural = mo.pluralize(word)
            qw_form = "kuantas" if gender == "f" else "kuantos"
            n = self.r.choice([2, 3, 4, 5, 7, 10])
            q = f"{qw_form} {plural} ai aki?"
            ans = cap(f"ai {lx.number_word(n)} {plural}") + "."
        elif qw == "komo":
            q = "komo estas tu?"
            ans = self.r.choice(["Yo so muy bien, grasi.", "So bien.",
                                 "No muy bien, ma bien.", "Muy bien!"])
        elif qw == "porke":
            q = f"porke {self.declarative_core()}?"
            ans = cap("porke " + self.declarative_core()) + "."
        else:  # ke + transitive verb: "what does X do?"
            verb = self.r.choice([v for v in lx.VERBS if v[1][0] == "tr"])
            subj = self.subject("human")
            person = subj["person"]
            v = mo.conjugate(verb[0], person)
            who = subj["text"] or mo.subject_pronoun(person, subj["gender"])
            q = f"ke {v} {who}?"
            obj, *_ = self.noun_phrase(verb[1][2])
            ans = cap(f"{who} {v} {obj}") + "."
        return cap(q), ans

    def _short_answer(self):
        if self.r.random() < 0.5:
            return self.r.choice(["Si.", "Si, klaro.", "Si, es vero.",
                                  "Klaro ke si."])
        return self.r.choice(["No.", "No, no es vero.", "No ankor.",
                              "No, pra nada."])

    # -- genre documents -----------------------------------------------------
    def doc_frase(self):
        return "[FRASE] " + self.declarative()

    def doc_qa(self):
        q, a = self.question()
        return f"[QA] {q} {a}"

    def doc_salu(self):
        opener = self.r.choice(["Salú!", "Bon jorno!", "Bona tarda!", "Ola!"])
        turns = [f"— {opener}"]
        turns.append("— " + self.r.choice(
            ["Salú, amiko!", "Bon jorno! Komo estas?", "Ola, ke tal?",
             "Bona tarda! Komo te va?"]))
        turns.append("— " + self.r.choice(
            ["Yo so muy bien, grasi. E tu?", "Bien, bien. E tu, komo estas?",
             "Tuto bien, mersi. E tu?"]))
        turns.append("— " + self.r.choice(
            ["Tanben bien. Asta pronto!", "Muy bien tanben. Adiu!",
             "Bien, grasi. Asta manyana!", "Kontento de te vider. Adiu!"]))
        return "[SALU] " + " ".join(turns)

    def doc_dialog(self):
        n = self.r.randint(2, 4)
        turns = []
        for i in range(n):
            if self.r.random() < 0.5:
                q, a = self.question()
                turns.append("— " + q)
                turns.append("— " + a)
            else:
                turns.append("— " + self.declarative())
        return "[DIALOG] " + " ".join(turns)

    def doc_historia(self):
        n = self.r.randint(2, 4)
        # a "protagonist" NP that anchors the paragraph
        hero, hgender = self.pick_noun(["human"])
        art = mo.article(True, hgender, "s")
        opener = self.r.choice([
            f"{art} {hero} viveva en una peti sivda.",
            f"Un jorno, {art} {hero} sali de su kasa.",
            f"Avan mucho tempo, {art} {hero} andava sur un longo kamin.",
            f"{art} {hero} era joven e felis.",
        ])
        sents = [opener]
        for _ in range(n):
            sents.append(self.declarative())
        closer = self.r.choice([
            "E asi, tuto finiva bien.",
            "Depos akel jorno, tuto kambiava.",
            "E le sol brilava sur le mundo.",
            "E eli viven felis por sempre.",
        ])
        sents.append(closer)
        return "[HISTORIA] " + " ".join(cap(s) for s in sents)

    def document(self):
        kind = self.r.choices(
            ["frase", "qa", "dialog", "historia", "salu"],
            weights=[40, 20, 16, 14, 10])[0]
        return getattr(self, f"doc_{kind}")()


if __name__ == "__main__":
    g = Gen(7)
    for _ in range(12):
        print(g.document())
        print()
