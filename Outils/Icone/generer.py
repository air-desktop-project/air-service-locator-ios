#!/usr/bin/env python3
"""L'icône d'air-service-locator, dessinée par programme — une seule géométrie,
trois plates-formes.

# Ce qu'elle montre

Un point d'écoute (le disque), la machine qui le tient (l'anneau), et
l'annuaire qui le sonde (les deux arcs, vers le haut à droite) : « vos
machines, leurs daemons, et le port où les joindre ». Rien d'autre — une
icône se lit à 16 pixels, dans une barre de menus, ou pas du tout.

# Ce qu'il produit

  AppIcon-iOS-1024.png            plein cadre : iOS arrondit lui-même
  AppIcon-macOS-<n>.png           16 … 1024 : la forme arrondie de macOS 11+,
                                  sur marge transparente, avec son ombre
  BarreDeMenus.png, @2x           le motif seul, noir sur transparent, pour la
                                  barre de menus (image « modèle »)
  android/ic_launcher_foreground.xml   le motif, en VectorDrawable, pour
                                       l'icône adaptative (zone sûre : 66 %)
  android/ic_launcher_background.xml   le fond

Tout est dérivé des mêmes constantes ci-dessous. Pillow suffit : on dessine
en 4× et l'on réduit, ce qui vaut un anticrénelage.
"""

from pathlib import Path
import math

from PIL import Image, ImageDraw, ImageFilter

BLEU_HAUT = (0x3D, 0x82, 0xCE)
BLEU_BAS = (0x1E, 0x4E, 0x8A)
BLANC = (255, 255, 255)

# La géométrie, sur un carré de 1024, origine en haut à gauche. Le motif est
# décalé en bas à gauche pour laisser place aux arcs.
CENTRE = (436.0, 588.0)
DISQUE = 58.0
ANNEAU = 158.0
ARCS = (312.0, 452.0)
TRAIT = 66.0
ARC_DEBUT, ARC_FIN = -72.0, -18.0  # degrés, sens horaire, 0 = est ; vers le haut à droite


def fond(taille: int, rayon: float, echelle: int = 4) -> Image.Image:
    """Le dégradé bleu, découpé au carré arrondi de ce rayon (0 = plein cadre)."""
    t = taille * echelle
    degrade = Image.new("RGB", (1, t))
    for y in range(t):
        f = y / (t - 1)
        degrade.putpixel((0, y), tuple(round(BLEU_HAUT[i] * (1 - f) + BLEU_BAS[i] * f) for i in range(3)))
    image = degrade.resize((t, t))
    masque = Image.new("L", (t, t), 0)
    ImageDraw.Draw(masque).rounded_rectangle((0, 0, t - 1, t - 1), radius=rayon * echelle, fill=255)
    image.putalpha(masque)
    return image


def motif(dessin: ImageDraw.ImageDraw, echelle: float, decalage: tuple[float, float] = (0.0, 0.0)) -> None:
    """Le motif blanc, à cette échelle (1 = 1024 px), décalé de ce vecteur."""
    cx, cy = CENTRE[0] * echelle + decalage[0], CENTRE[1] * echelle + decalage[1]
    trait = max(1, round(TRAIT * echelle))

    def boite(r: float) -> tuple[float, float, float, float]:
        return (cx - r * echelle, cy - r * echelle, cx + r * echelle, cy + r * echelle)

    dessin.ellipse(boite(DISQUE), fill=BLANC)
    dessin.ellipse(boite(ANNEAU), outline=BLANC, width=trait)
    for r in ARCS:
        # Pillow trace un arc VERS L'INTÉRIEUR de sa boîte : `r` est le bord
        # externe du trait, et son milieu est à `r - TRAIT / 2`.
        dessin.arc(boite(r), start=ARC_DEBUT, end=ARC_FIN, fill=BLANC, width=trait)
        # Des bouts ronds : Pillow n'en trace pas, un disque à chaque extrémité les fait.
        milieu = (r - TRAIT / 2) * echelle
        for angle in (ARC_DEBUT, ARC_FIN):
            a = math.radians(angle)
            px, py = cx + milieu * math.cos(a), cy + milieu * math.sin(a)
            dessin.ellipse((px - trait / 2, py - trait / 2, px + trait / 2, py + trait / 2), fill=BLANC)


def icone(taille: int, rayon: float, echelle: int = 4) -> Image.Image:
    image = fond(taille, rayon, echelle)
    motif(ImageDraw.Draw(image), taille * echelle / 1024)
    return image.resize((taille, taille), Image.LANCZOS)


def ios(sortie: Path) -> None:
    icone(1024, 0).convert("RGB").save(sortie / "AppIcon-iOS-1024.png")


def macos(sortie: Path) -> None:
    """La forme de macOS 11+ : l'icône occupe 824/1024, coins à 185, une ombre
    douce en dessous. Chaque taille est rendue à part, jamais réduite d'une
    autre : un anneau de 16 px n'est pas un anneau de 1024 px divisé par 64."""
    for taille in (16, 32, 64, 128, 256, 512, 1024):
        echelle = 4
        t = taille * echelle
        toile = Image.new("RGBA", (t, t), (0, 0, 0, 0))
        interieur = round(t * 824 / 1024)
        marge = (t - interieur) // 2
        ombre = Image.new("RGBA", (t, t), (0, 0, 0, 0))
        ImageDraw.Draw(ombre).rounded_rectangle(
            (marge, marge + t * 0.012, marge + interieur, marge + interieur + t * 0.012),
            radius=interieur * 185 / 824, fill=(0, 0, 0, 70),
        )
        ombre = ombre.filter(ImageFilter.GaussianBlur(t * 0.01))
        toile.alpha_composite(ombre)
        carre = fond(interieur // echelle, interieur // echelle * 185 / 824, echelle)
        motif(ImageDraw.Draw(carre), interieur / 1024)
        toile.alpha_composite(carre, (marge, marge))
        toile.resize((taille, taille), Image.LANCZOS).save(sortie / f"AppIcon-macOS-{taille}.png")


def android(sortie: Path) -> None:
    """L'icône adaptative : le fond en couleur, le motif en chemins vectoriels.
    Le canevas fait 108 dp et la zone sûre les 66 % du centre : le motif de
    1024 est ramené à 72 dp, centré."""
    dossier = sortie / "android"
    dossier.mkdir(exist_ok=True)
    k = 72 / 1024
    ox, oy = 18.0, 18.0

    def p(v: float) -> str:
        return f"{v:.2f}"

    cx, cy = ox + CENTRE[0] * k, oy + CENTRE[1] * k
    trait = TRAIT * k
    chemins = [
        # Le disque, plein.
        f'    <path android:fillColor="#FFFFFF" android:pathData="M{p(cx - DISQUE * k)},{p(cy)} '
        f'a{p(DISQUE * k)},{p(DISQUE * k)} 0 1,0 {p(2 * DISQUE * k)},0 a{p(DISQUE * k)},{p(DISQUE * k)} 0 1,0 -{p(2 * DISQUE * k)},0z"/>',
        # L'anneau, en trait.
        f'    <path android:strokeColor="#FFFFFF" android:strokeWidth="{p(trait)}" android:fillColor="#00000000" '
        f'android:pathData="M{p(cx - (ANNEAU - TRAIT / 2) * k)},{p(cy)} a{p((ANNEAU - TRAIT / 2) * k)},{p((ANNEAU - TRAIT / 2) * k)} 0 1,0 {p(2 * (ANNEAU - TRAIT / 2) * k)},0 '
        f'a{p((ANNEAU - TRAIT / 2) * k)},{p((ANNEAU - TRAIT / 2) * k)} 0 1,0 -{p(2 * (ANNEAU - TRAIT / 2) * k)},0z"/>',
    ]
    for rayon_externe in ARCS:
        r = rayon_externe - TRAIT / 2  # le milieu du trait, là où Pillow le dessine
        a0, a1 = math.radians(ARC_DEBUT), math.radians(ARC_FIN)
        x0, y0 = cx + r * k * math.cos(a0), cy + r * k * math.sin(a0)
        x1, y1 = cx + r * k * math.cos(a1), cy + r * k * math.sin(a1)
        chemins.append(
            f'    <path android:strokeColor="#FFFFFF" android:strokeWidth="{p(trait)}" android:strokeLineCap="round" '
            f'android:fillColor="#00000000" android:pathData="M{p(x0)},{p(y0)} A{p(r * k)},{p(r * k)} 0 0,1 {p(x1)},{p(y1)}"/>'
        )
    (dossier / "ic_launcher_foreground.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<!-- Généré par Outils/Icone/generer.py du dépôt iOS : ne pas retoucher à la main. -->\n"
        '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
        '    android:width="108dp" android:height="108dp"\n'
        '    android:viewportWidth="108" android:viewportHeight="108">\n'
        + "\n".join(chemins) + "\n</vector>\n"
    )
    (dossier / "ic_launcher_background.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<!-- Généré par Outils/Icone/generer.py du dépôt iOS : ne pas retoucher à la main. -->\n"
        '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
        '    android:width="108dp" android:height="108dp"\n'
        '    android:viewportWidth="108" android:viewportHeight="108">\n'
        '    <path android:pathData="M0,0h108v108h-108z">\n'
        '        <aapt:attr xmlns:aapt="http://schemas.android.com/aapt" name="android:fillColor">\n'
        f'            <gradient android:startY="0" android:startX="54" android:endY="108" android:endX="54" android:type="linear">\n'
        f'                <item android:offset="0" android:color="#{BLEU_HAUT[0]:02X}{BLEU_HAUT[1]:02X}{BLEU_HAUT[2]:02X}"/>\n'
        f'                <item android:offset="1" android:color="#{BLEU_BAS[0]:02X}{BLEU_BAS[1]:02X}{BLEU_BAS[2]:02X}"/>\n'
        "            </gradient>\n        </aapt:attr>\n    </path>\n</vector>\n"
    )


def barre_de_menus(sortie: Path) -> None:
    """Le motif seul, en noir sur transparent, pour la barre de menus de
    macOS : une image « modèle », que le système teinte selon le fond. Le
    motif est cadré au plus juste — pas de fond, pas de marge d'icône — pour
    lire à 18 points."""
    # La boîte du motif sur le canevas de 1024.
    gauche, haut = CENTRE[0] - ANNEAU, CENTRE[1] + max(ARCS) * math.sin(math.radians(ARC_DEBUT))
    droite, bas = CENTRE[0] + max(ARCS) * math.cos(math.radians(ARC_FIN)), CENTRE[1] + ANNEAU
    largeur, hauteur = droite - gauche, bas - haut
    for points, facteur in ((18, 1), (18, 2)):
        taille = points * facteur
        echelle = 4
        t = taille * echelle
        utile = (taille - 2) * echelle  # un point de marge de chaque côté
        k = utile / max(largeur, hauteur)
        toile = Image.new("RGBA", (t, t), (0, 0, 0, 0))
        dessin = ImageDraw.Draw(toile)
        # `motif` dessine en blanc : on dessine, puis l'on garde l'alpha pour du noir.
        dx = (t - largeur * k) / 2 - gauche * k
        dy = (t - hauteur * k) / 2 - haut * k
        motif(dessin, k, (dx, dy))
        alpha = toile.split()[3].resize((taille, taille), Image.LANCZOS)
        noir = Image.new("RGBA", (taille, taille), (0, 0, 0, 255))
        noir.putalpha(alpha)
        suffixe = "" if facteur == 1 else f"@{facteur}x"
        noir.save(sortie / f"BarreDeMenus{suffixe}.png")


if __name__ == "__main__":
    sortie = Path(__file__).resolve().parent / "sortie"
    sortie.mkdir(exist_ok=True)
    ios(sortie)
    macos(sortie)
    android(sortie)
    barre_de_menus(sortie)
    print(f"icônes dans {sortie}/")
