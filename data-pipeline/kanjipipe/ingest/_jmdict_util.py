"""Shared helpers for the JMdict word and relation parsers."""


def preferred_keb(entry) -> str | None:
    """The entry's preferred surface: first kanji form (keb) not marked
    irregular/outdated (ke_inf); falls back to the first keb if all are marked."""
    k_eles = entry.findall("k_ele")
    for k_ele in k_eles:
        keb = k_ele.findtext("keb")
        if keb and k_ele.find("ke_inf") is None:
            return keb
    return (k_eles[0].findtext("keb") if k_eles else None) or None
