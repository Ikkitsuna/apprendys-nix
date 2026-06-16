#!/usr/bin/env python3
"""Apprendys — Mon Apprendys (personnalisation + espace parent PIN).

Port V2 (NixOS) de l'app beta V1. Différences clés :
- profils nommés par STYLE (Mignon/Classique/Monochrome), pas par âge —
  l'apparence décrit le look, jamais la personne (décision Florent 12/06) ;
- l'application d'un profil passe par apprendys-session-init (idempotent) :
  icônes + ambiance complète (fond, thème GTK, densité) suivent d'un coup ;
- prénom (Whisker) → systemctl start apprendys-prenom.service (GECOS),
  autorisé par règle polkit (base.nix) ;
- bouton MAJ → systemctl start apprendys-ota.service (règle polkit
  ota-installed.nix), affiché seulement si le service existe (installé) ;
- aucune commande qui (re)lance un démon n'est lancée avec capture de tuyau
  (sinon gel) : voir _spawn/_run ;
- guides HTML embarqués dans le store (chemin substitué au build).
Les chemins @...@ sont substitués par packages/apprendys-app.nix.
"""
import gi, os, subprocess, glob, time, json, hashlib, threading
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, GdkPixbuf, Pango, GLib

DEVNULL = subprocess.DEVNULL


def _spawn(cmd, env):
    """Lance un processus sans capturer ses tuyaux. CRITIQUE : capturer
    stdout/stderr (capture_output=True) d'une commande qui (re)lance un
    démon — xfce4-panel --restart, xfdesktop, xfsettingsd — fait hériter
    le tuyau au démon, qui ne le ferme jamais → l'appelant gèle. DEVNULL
    + nouvelle session = aucun héritage, aucun gel."""
    try:
        subprocess.Popen(cmd, env=env, stdin=DEVNULL, stdout=DEVNULL,
                         stderr=DEVNULL, start_new_session=True)
    except Exception:
        pass


def _run(cmd, env, timeout=30):
    """run() qui ATTEND la fin mais sans capture de tuyau (même piège que
    _spawn si la commande backgroundise un démon). DEVNULL partout."""
    try:
        return subprocess.run(cmd, env=env, stdin=DEVNULL, stdout=DEVNULL,
                              stderr=DEVNULL, timeout=timeout).returncode
    except Exception:
        return 1


def ota_available():
    """Le service OTA n'existe que sur le système INSTALLÉ (pas l'ISO live :
    un squashfs en lecture seule ne se met pas à jour). On masque le bouton
    MAJ si le service est absent → pas de demande de mot de passe inutile."""
    try:
        return subprocess.run(['systemctl', 'cat', 'apprendys-ota.service'],
                              stdin=DEVNULL, stdout=DEVNULL, stderr=DEVNULL,
                              timeout=5).returncode == 0
    except Exception:
        return False

CONFIG_DIR   = os.path.expanduser('~/.config/apprendys')
ICON_BASE    = os.path.expanduser('~/.local/share/icons/apprendys')
ICON_CONFIG  = os.path.join(CONFIG_DIR, 'icon-set')
NAME_CONFIG  = os.path.join(CONFIG_DIR, 'user-name')
PIN_CONFIG   = os.path.join(CONFIG_DIR, 'parent-pin')
TTS_CONFIG   = os.path.join(CONFIG_DIR, 'tts-speed')
FONT_STYLE   = os.path.join(CONFIG_DIR, 'font-style')   # luciole | opendyslexic
FONT_SIZE    = os.path.join(CONFIG_DIR, 'font-size')    # 14 | 16 | 18
CURSOR_SIZE  = os.path.join(CONFIG_DIR, 'cursor-size')  # 24 | 48
CHANGELOG    = '@changelog@'
GUIDES_INDEX = '@guides@/index.html'
VERSION_FILE = '/run/current-system/nixos-version'

# (clé icon-set, nom du style, description du STYLE — jamais de l'utilisateur)
PROFILES = [
    ('junior', 'Mignon',     'Doux et coloré'),
    ('teen',   'Classique',  'Bleu, apaisant'),
    ('adult',  'Monochrome', 'Sobre, contrasté'),
]

FONT_PROFILES = [
    ('luciole',      'Standard',  'Luciole',       'Pour tous'),
    ('opendyslexic', 'Dyslexie',  'OpenDyslexic',  'Lecture facilitée'),
]

FONT_SIZES = [
    (14, 'S'),
    (16, 'M'),
    (18, 'G'),
]

CSS = b"""
window { background: #F8F9FA; }
.app-title    { font-size: 20px; font-weight: bold; color: #2D3748; }
.ver-badge    { font-size: 10px; color: #A0AEC0; }
.greeting     { font-size: 16px; font-weight: bold; color: #2D3748; }
.sub          { font-size: 13px; color: #718096; }
.link-btn     { color: #77B4CE; border: none; background: transparent;
                padding: 0 2px; font-size: 12px; }
.card         { border-radius: 14px; background: white;
                border: 3px solid transparent; }
.card:hover   { border-color: #CBD5E0; }
.card.active  { border-color: #77B4CE; background: #EBF8FF; }
.card-name    { font-size: 14px; font-weight: bold; color: #2D3748; }
.card-age     { font-size: 11px; color: #718096; }
.card-dark    { border-radius: 8px; background: #36404A; }
.size-btn     { border-radius: 8px; background: white; border: 2px solid #E2E8F0;
                font-size: 13px; min-width: 44px; }
.size-btn.active { border-color: #77B4CE; background: #EBF8FF;
                   color: #2B6CB0; font-weight: bold; }
.toggle-btn   { border-radius: 8px; background: white; border: 2px solid #E2E8F0;
                font-size: 12px; }
.toggle-btn.active { border-color: #77B4CE; background: #EBF8FF; color: #2B6CB0; }
.primary-btn  { background: #77B4CE; color: white; border-radius: 10px;
                font-size: 13px; border: none; font-weight: bold; }
.secondary-btn{ background: #EDF2F7; color: #4A5568; border-radius: 10px;
                font-size: 12px; border: none; }
.section-lbl  { font-size: 13px; font-weight: bold; color: #4A5568; }
.cl-version   { font-size: 12px; font-weight: bold; color: #77B4CE; }
.cl-title     { font-size: 12px; color: #2D3748; }
.cl-row-hover { border-radius: 8px; }
.cl-row-hover:hover { background: #EBF8FF; }
.cl-date      { font-size: 11px; color: #A0AEC0; }
.tag-feature  { font-size: 10px; color: #276749; }
.tag-fix      { font-size: 10px; color: #2A4365; }
.tag-security { font-size: 10px; color: #744210; }
.parent-title { font-size: 15px; font-weight: bold; color: #2D3748; }
"""


def read_cfg(path, default=''):
    try:
        return open(path).read().strip()
    except Exception:
        return default


def write_cfg(path, value):
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, 'w') as f:
            f.write(str(value) + '\n')
        return True
    except Exception:
        return False


def pin_hash(pin):
    return hashlib.sha256(pin.encode()).hexdigest()


def has_pin():
    return bool(read_cfg(PIN_CONFIG))


def check_pin(pin):
    stored = read_cfg(PIN_CONFIG)
    return stored and stored == pin_hash(pin)


def apply_profile(profile, env):
    """V2 : on écrit icon-set puis session-init applique TOUT (icônes,
    fond, thème GTK, densité, panel) — source de vérité unique.
    session-init relance déjà le panel ; on ne le refait donc PAS ici
    (c'était la source du gel). DEVNULL obligatoire : session-init
    backgroundise un xfce4-panel --restart qui hériterait du tuyau."""
    if not os.path.isdir(os.path.join(ICON_BASE, profile)):
        return False
    write_cfg(ICON_CONFIG, profile)
    _run(['apprendys-session-init'], env, timeout=60)
    # xfdesktop met en cache les icônes du bureau (même chemin, PNG changé)
    # → il faut le relancer pour qu'il relise les nouvelles icônes.
    _run(['pkill', 'xfdesktop'], env, timeout=5)
    time.sleep(1)
    _spawn(['xfdesktop'], env)
    return True


def apply_reading(style, size, env):
    """Applique la police + taille via xsettings. session-init relit
    font-style/font-size au login et respecte ce choix."""
    font_map = {'luciole': 'Luciole', 'opendyslexic': 'OpenDyslexic'}
    font_name = font_map.get(style, 'Luciole')
    full_font = f'{font_name} {size}'
    subprocess.run(['xfconf-query', '-c', 'xsettings',
                    '-p', '/Gtk/FontName', '-s', full_font],
                   env=env, capture_output=True)
    subprocess.run(['xfconf-query', '-c', 'xfwm4',
                    '-p', '/general/title_font', '-s', full_font],
                   env=env, capture_output=True)
    if subprocess.run(['pgrep', 'xfsettingsd'],
                      capture_output=True).returncode != 0:
        _spawn(['xfsettingsd', '--daemon'], env)
    write_cfg(FONT_STYLE, style)
    write_cfg(FONT_SIZE, str(size))


def apply_cursor(size, env):
    """Applique la taille du curseur via xsettings + xrdb."""
    subprocess.run(['xfconf-query', '-c', 'xsettings',
                    '-p', '/Gtk/CursorThemeSize', '-s', str(size)],
                   env=env, capture_output=True)
    subprocess.run(['xrdb', '-merge'],
                   input=f'Xcursor.size: {size}\n'.encode(),
                   env=env, capture_output=True)
    if subprocess.run(['pgrep', 'xfsettingsd'],
                      capture_output=True).returncode != 0:
        _spawn(['xfsettingsd', '--daemon'], env)
    write_cfg(CURSOR_SIZE, str(size))


def load_changelog():
    try:
        with open(CHANGELOG) as f:
            data = json.load(f)
        entries = sorted(
            data.items(),
            key=lambda x: [int(n) for n in x[0].split('.')],
            reverse=True
        )
        return entries[:5]
    except Exception:
        return []


def apply_user_name(env):
    """L'en-tête du menu Whisker affiche le NOM COMPLET du compte (GECOS),
    pas une propriété xfconf. On déclenche apprendys-prenom.service (oneshot,
    privilégié via règle polkit dans base.nix) : il relit
    ~/.config/apprendys/user-name et fait `usermod -c`. Puis on relance le
    panel pour que Whisker relise le GECOS. Sur un système sans le service
    ni la règle, le start échoue silencieusement (best-effort)."""
    _run(['systemctl', 'start', 'apprendys-prenom.service'], env, timeout=15)
    _spawn(['xfce4-panel', '--restart'], env)


class MonApprendys(Gtk.Window):
    def __init__(self):
        super().__init__(title='Mon Apprendys')
        self.set_default_size(500, 620)
        self.set_resizable(True)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.connect('destroy', Gtk.main_quit)

        provider = Gtk.CssProvider()
        provider.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(
            self.get_screen(), provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

        self.env = os.environ.copy()
        self.env.setdefault('DISPLAY', ':0')
        self.env.setdefault('DBUS_SESSION_BUS_ADDRESS',
                            'unix:path=/run/user/1000/bus')

        self.user_name        = read_cfg(NAME_CONFIG)
        self.profile_cards    = {}
        self.font_cards       = {}
        self.size_btns        = {}
        self.cursor_btns      = {}

        # État sauvegardé (= ce qui est sur disque)
        self.saved_profile    = read_cfg(ICON_CONFIG, 'junior')
        self.saved_font_style = read_cfg(FONT_STYLE, 'luciole')
        self.saved_font_size  = int(read_cfg(FONT_SIZE, '14') or '14')
        self.saved_cursor_sz  = int(read_cfg(CURSOR_SIZE, '24') or '24')

        # Sélection courante (peut différer du sauvegardé)
        self.sel_profile      = self.saved_profile
        self.sel_font_style   = self.saved_font_style
        self.sel_font_size    = self.saved_font_size
        self.sel_cursor_sz    = self.saved_cursor_sz

        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.add(root)
        root.pack_start(self._build_header(), False, False, 0)

        self.stack = Gtk.Stack()
        self.stack.set_transition_type(Gtk.StackTransitionType.SLIDE_LEFT_RIGHT)
        self.stack.set_transition_duration(180)
        root.pack_start(self.stack, True, True, 0)

        self.stack.add_named(self._build_child_space(), 'child')
        self.stack.add_named(self._build_parent_space(), 'parent')
        self.stack.set_visible_child_name('child')
        self.connect('delete-event', self._on_close)

    # ------------------------------------------------------------------ #
    # Header                                                               #
    # ------------------------------------------------------------------ #
    def _build_header(self):
        hbox = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        hbox.set_margin_top(20)
        hbox.set_margin_bottom(6)
        hbox.set_margin_start(28)
        hbox.set_margin_end(28)

        title = Gtk.Label(label='Mon Apprendys')
        title.get_style_context().add_class('app-title')
        title.set_halign(Gtk.Align.START)
        hbox.pack_start(title, True, True, 0)

        ver = read_cfg(VERSION_FILE, '?')
        ver_lbl = Gtk.Label(label=f'v{ver}')
        ver_lbl.get_style_context().add_class('ver-badge')
        hbox.pack_end(ver_lbl, False, False, 0)
        return hbox

    # ------------------------------------------------------------------ #
    # Espace enfant (scrollable)                                           #
    # ------------------------------------------------------------------ #
    def _build_child_space(self):
        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        box.set_margin_start(28)
        box.set_margin_end(28)
        box.set_margin_top(4)
        box.set_margin_bottom(20)

        # Greeting + prénom
        self.greeting_lbl = Gtk.Label()
        self.greeting_lbl.get_style_context().add_class('greeting')
        self.greeting_lbl.set_halign(Gtk.Align.START)
        self._refresh_greeting()
        box.pack_start(self.greeting_lbl, False, False, 0)

        name_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        self.name_btn = Gtk.Button()
        self.name_btn.get_style_context().add_class('link-btn')
        self._refresh_name_btn()
        self.name_btn.connect('clicked', self._on_change_name)
        name_row.pack_start(self.name_btn, False, False, 0)
        box.pack_start(name_row, False, False, 0)

        box.pack_start(Gtk.Separator(), False, False, 4)

        # ---- Style ----
        sub_icons = Gtk.Label(label="🎨  Mon style")
        sub_icons.get_style_context().add_class('section-lbl')
        sub_icons.set_halign(Gtk.Align.START)
        box.pack_start(sub_icons, False, False, 0)

        cards_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        for key, label, desc in PROFILES:
            cards_row.pack_start(self._make_icon_card(key, label, desc), True, True, 0)
        box.pack_start(cards_row, False, False, 0)

        box.pack_start(Gtk.Separator(), False, False, 4)

        # ---- Lecture ----
        sub_read = Gtk.Label(label="📖  Police de lecture")
        sub_read.get_style_context().add_class('section-lbl')
        sub_read.set_halign(Gtk.Align.START)
        box.pack_start(sub_read, False, False, 0)

        font_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        for key, label, font_name, desc in FONT_PROFILES:
            font_row.pack_start(self._make_font_card(key, label, font_name, desc), True, True, 0)
        box.pack_start(font_row, False, False, 0)

        # Taille du texte
        size_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        size_lbl = Gtk.Label(label='Taille :')
        size_lbl.get_style_context().add_class('sub')
        size_row.pack_start(size_lbl, False, False, 0)
        for sz, letter in FONT_SIZES:
            btn = Gtk.Button(label=letter)
            btn.get_style_context().add_class('size-btn')
            if sz == self.sel_font_size:
                btn.get_style_context().add_class('active')
            btn.connect('clicked', self._on_font_size, sz)
            self.size_btns[sz] = btn
            size_row.pack_start(btn, False, False, 0)
        box.pack_start(size_row, False, False, 0)

        # Curseur
        cursor_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        cursor_lbl = Gtk.Label(label='Curseur :')
        cursor_lbl.get_style_context().add_class('sub')
        cursor_row.pack_start(cursor_lbl, False, False, 0)
        for sz, label in ((24, 'Normal'), (48, 'Grand')):
            btn = Gtk.Button(label=label)
            btn.get_style_context().add_class('toggle-btn')
            if sz == self.sel_cursor_sz:
                btn.get_style_context().add_class('active')
            btn.connect('clicked', self._on_cursor_size, sz)
            self.cursor_btns[sz] = btn
            cursor_row.pack_start(btn, False, False, 0)
        box.pack_start(cursor_row, False, False, 0)

        box.pack_start(Gtk.Separator(), False, False, 4)

        # Bouton Appliquer global
        self.apply_btn = Gtk.Button(label='✅  Appliquer les changements')
        self.apply_btn.get_style_context().add_class('primary-btn')
        self.apply_btn.connect('clicked', self._on_apply_all)
        box.pack_start(self.apply_btn, False, False, 0)

        # Bas de page
        guide_btn = Gtk.Button(label='📖  Guides et tutoriels')
        guide_btn.get_style_context().add_class('secondary-btn')
        guide_btn.connect('clicked', self._on_show_guide)
        box.pack_start(guide_btn, False, False, 0)

        parent_btn = Gtk.Button(label='🔒  Espace parent')
        parent_btn.get_style_context().add_class('secondary-btn')
        parent_btn.connect('clicked', self._on_parent_click)
        box.pack_start(parent_btn, False, False, 0)

        scroll.add(box)
        return scroll

    def _make_icon_card(self, key, label, desc):
        card = Gtk.EventBox()
        card.get_style_context().add_class('card')
        if key == self.saved_profile:
            card.get_style_context().add_class('active')
        card.connect('button-press-event', self._on_card_click, key)

        inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        inner.set_margin_top(12)
        inner.set_margin_bottom(12)
        inner.set_margin_start(8)
        inner.set_margin_end(8)

        icon_path = os.path.join(ICON_BASE, key, 'mes-devoirs.png')
        if os.path.exists(icon_path):
            try:
                pb = GdkPixbuf.Pixbuf.new_from_file_at_scale(icon_path, 40, 40, True)
                img = Gtk.Image.new_from_pixbuf(pb)
                if key == 'adult':
                    # icônes blanches : fond sombre derrière l'aperçu, sinon
                    # blanc sur blanc = invisible dans la carte
                    holder = Gtk.EventBox()
                    holder.get_style_context().add_class('card-dark')
                    img.set_margin_top(4); img.set_margin_bottom(4)
                    img.set_margin_start(4); img.set_margin_end(4)
                    holder.add(img)
                    holder.set_halign(Gtk.Align.CENTER)
                    inner.pack_start(holder, False, False, 0)
                else:
                    inner.pack_start(img, False, False, 0)
            except Exception:
                pass

        lbl = Gtk.Label(label=label)
        lbl.get_style_context().add_class('card-name')
        inner.pack_start(lbl, False, False, 0)

        desc_lbl = Gtk.Label(label=desc)
        desc_lbl.get_style_context().add_class('card-age')
        inner.pack_start(desc_lbl, False, False, 0)

        card.add(inner)
        self.profile_cards[key] = card
        return card

    def _make_font_card(self, key, label, font_name, desc):
        card = Gtk.EventBox()
        card.get_style_context().add_class('card')
        if key == self.saved_font_style:
            card.get_style_context().add_class('active')
        card.connect('button-press-event', self._on_font_card_click, key)

        inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        inner.set_margin_top(14)
        inner.set_margin_bottom(12)
        inner.set_margin_start(10)
        inner.set_margin_end(10)

        # Preview du texte dans la vraie police
        preview = Gtk.Label()
        preview.set_markup(
            f'<span font="{font_name} 15"><b>Aa</b> Bb</span>\n'
            f'<span font="{font_name} 11">1 2 3</span>'
        )
        preview.set_justify(Gtk.Justification.CENTER)
        inner.pack_start(preview, False, False, 0)

        name_lbl = Gtk.Label(label=label)
        name_lbl.get_style_context().add_class('card-name')
        inner.pack_start(name_lbl, False, False, 0)

        desc_lbl = Gtk.Label(label=desc)
        desc_lbl.get_style_context().add_class('card-age')
        inner.pack_start(desc_lbl, False, False, 0)

        card.add(inner)
        self.font_cards[key] = card
        return card

    # ------------------------------------------------------------------ #
    # Espace parent                                                        #
    # ------------------------------------------------------------------ #
    def _build_parent_space(self):
        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        outer.set_margin_start(28)
        outer.set_margin_end(28)
        outer.set_margin_bottom(16)

        hdr = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        back = Gtk.Button(label='← Retour')
        back.get_style_context().add_class('secondary-btn')
        back.connect('clicked', lambda b: self.stack.set_visible_child_name('child'))
        hdr.pack_start(back, False, False, 0)

        ptitle = Gtk.Label(label='⚙️  Paramètres parents')
        ptitle.get_style_context().add_class('parent-title')
        ptitle.set_halign(Gtk.Align.START)
        hdr.pack_start(ptitle, True, True, 8)
        outer.pack_start(hdr, False, False, 16)

        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        content.set_margin_bottom(8)

        # Changelog (cliquable → détail)
        cl_lbl = Gtk.Label(label='📋  Dernières mises à jour')
        cl_lbl.get_style_context().add_class('section-lbl')
        cl_lbl.set_halign(Gtk.Align.START)
        content.pack_start(cl_lbl, False, False, 0)
        cl_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        entries = load_changelog()
        if entries:
            for ver, info in entries:
                cl_box.pack_start(self._make_cl_row(ver, info), False, False, 0)
        else:
            no = Gtk.Label(label='Aucune information disponible.')
            no.get_style_context().add_class('sub')
            cl_box.pack_start(no, False, False, 0)
        content.pack_start(cl_box, False, False, 0)

        # MAJ — bouton seulement si le service OTA existe (système installé).
        # Sur l'ISO live : rien à mettre à jour, et déclencher le service
        # ferait apparaître une demande de mot de passe (pas de règle polkit).
        content.pack_start(Gtk.Separator(), False, False, 0)
        maj_lbl = Gtk.Label(label='🔄  Mise à jour')
        maj_lbl.get_style_context().add_class('section-lbl')
        maj_lbl.set_halign(Gtk.Align.START)
        content.pack_start(maj_lbl, False, False, 0)

        maj_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        ver = read_cfg(VERSION_FILE, '?')
        if ota_available():
            info_lbl = Gtk.Label(label=f'Version {ver}')
            info_lbl.get_style_context().add_class('sub')
            info_lbl.set_halign(Gtk.Align.START)
            maj_row.pack_start(info_lbl, True, True, 0)

            self.update_btn = Gtk.Button(label='Vérifier maintenant')
            self.update_btn.get_style_context().add_class('primary-btn')
            self.update_btn.connect('clicked', self._on_update)
            maj_row.pack_end(self.update_btn, False, False, 0)
        else:
            info_lbl = Gtk.Label(
                label='Les mises à jour seront automatiques après installation.')
            info_lbl.get_style_context().add_class('sub')
            info_lbl.set_halign(Gtk.Align.START)
            info_lbl.set_line_wrap(True)
            maj_row.pack_start(info_lbl, True, True, 0)
        content.pack_start(maj_row, False, False, 0)

        # TTS speed
        content.pack_start(Gtk.Separator(), False, False, 0)
        tts_lbl = Gtk.Label(label='🎙️  Vitesse lecture voix haute')
        tts_lbl.get_style_context().add_class('section-lbl')
        tts_lbl.set_halign(Gtk.Align.START)
        content.pack_start(tts_lbl, False, False, 0)

        tts_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        lente = Gtk.Label(label='Lente')
        lente.get_style_context().add_class('sub')
        tts_val = float(read_cfg(TTS_CONFIG, '1.0') or '1.0')
        adj = Gtk.Adjustment(value=tts_val, lower=0.7, upper=1.5,
                             step_increment=0.1, page_increment=0.1)
        slider = Gtk.Scale(orientation=Gtk.Orientation.HORIZONTAL, adjustment=adj)
        slider.set_digits(1)
        slider.set_draw_value(True)
        slider.add_mark(1.0, Gtk.PositionType.BOTTOM, 'Normale')
        adj.connect('value-changed', lambda a: write_cfg(TTS_CONFIG, round(a.get_value(), 1)))
        rapide = Gtk.Label(label='Rapide')
        rapide.get_style_context().add_class('sub')
        tts_row.pack_start(lente, False, False, 0)
        tts_row.pack_start(slider, True, True, 0)
        tts_row.pack_start(rapide, False, False, 0)
        content.pack_start(tts_row, False, False, 0)

        scroll.add(content)
        outer.pack_start(scroll, True, True, 0)

        lock_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        lock_row.set_halign(Gtk.Align.END)
        lock_btn = Gtk.Button(label='🔒  Verrouiller')
        lock_btn.get_style_context().add_class('secondary-btn')
        lock_btn.connect('clicked', lambda b: self.stack.set_visible_child_name('child'))
        lock_row.pack_start(lock_btn, False, False, 0)
        outer.pack_start(lock_row, False, False, 12)
        return outer

    def _make_cl_row(self, version, info):
        # Ligne cliquable → ouvre dialog de détail
        evbox = Gtk.EventBox()
        evbox.get_style_context().add_class('cl-row-hover')

        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        row.set_margin_start(4); row.set_margin_top(2); row.set_margin_bottom(2)
        left = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        top = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)

        ver_lbl = Gtk.Label(label=f'v{version}')
        ver_lbl.get_style_context().add_class('cl-version')
        top.pack_start(ver_lbl, False, False, 0)

        title_lbl = Gtk.Label(label=info.get('titre', ''))
        title_lbl.get_style_context().add_class('cl-title')
        title_lbl.set_halign(Gtk.Align.START)
        top.pack_start(title_lbl, True, True, 0)

        tag_type = info.get('type', 'fix')
        tag_map = {'feature': '● Nouveauté', 'fix': '● Correction', 'security': '⚠ Sécurité'}
        tag_lbl = Gtk.Label(label=tag_map.get(tag_type, tag_type))
        tag_lbl.get_style_context().add_class(f'tag-{tag_type}')
        top.pack_end(tag_lbl, False, False, 0)

        left.pack_start(top, False, False, 0)
        date_lbl = Gtk.Label(label=info.get('date', ''))
        date_lbl.get_style_context().add_class('cl-date')
        date_lbl.set_halign(Gtk.Align.START)
        left.pack_start(date_lbl, False, False, 0)

        row.pack_start(left, True, True, 0)
        arrow = Gtk.Label(label='›')
        arrow.get_style_context().add_class('cl-date')
        row.pack_end(arrow, False, False, 4)

        evbox.add(row)
        evbox.connect('button-press-event',
                      lambda w, e: self._show_cl_detail(version, info))
        return evbox

    def _show_cl_detail(self, version, info):
        tag_type = info.get('type', 'fix')
        tag_map = {'feature': 'Nouveauté', 'fix': 'Correction', 'security': 'Sécurité'}
        dlg = Gtk.Dialog(title=f'v{version} — {info.get("titre", "")}',
                         transient_for=self, modal=True)
        dlg.set_default_size(420, -1)
        dlg.add_button('Fermer', Gtk.ResponseType.CLOSE)

        box = dlg.get_content_area()
        box.set_margin_start(18); box.set_margin_end(18)
        box.set_margin_top(12);   box.set_margin_bottom(8)
        box.set_spacing(10)

        # En-tête : tag + date
        meta = Gtk.Label(
            label=f'{tag_map.get(tag_type, tag_type)}  ·  {info.get("date", "")}')
        meta.get_style_context().add_class('cl-date')
        meta.set_halign(Gtk.Align.START)
        box.pack_start(meta, False, False, 0)

        # Résumé
        resume = info.get('resume', '')
        if resume:
            lbl = Gtk.Label(label=resume)
            lbl.set_halign(Gtk.Align.START)
            lbl.set_line_wrap(True)
            lbl.set_max_width_chars(52)
            lbl.get_style_context().add_class('sub')
            box.pack_start(lbl, False, False, 0)

        # Détails (puces optionnelles)
        details = info.get('details', [])
        if details:
            box.pack_start(Gtk.Separator(), False, False, 2)
            for item in details:
                puce = Gtk.Label(label=f'  •  {item}')
                puce.set_halign(Gtk.Align.START)
                puce.set_line_wrap(True)
                puce.set_max_width_chars(52)
                puce.get_style_context().add_class('sub')
                box.pack_start(puce, False, False, 0)

        box.show_all()
        dlg.run()
        dlg.destroy()

    # ------------------------------------------------------------------ #
    # Events — espace enfant                                               #
    # ------------------------------------------------------------------ #
    def _refresh_greeting(self):
        self.greeting_lbl.set_text(
            f'Bonjour {self.user_name} !' if self.user_name else 'Mon Apprendys')

    def _refresh_name_btn(self):
        self.name_btn.set_label(
            '✏️  Changer mon prénom' if self.user_name else '✏️  Entrer mon prénom')

    def _on_change_name(self, btn):
        dialog = Gtk.Dialog(title='Mon prénom', parent=self, flags=0)
        dialog.set_default_size(300, 100)
        dialog.add_button('Annuler', Gtk.ResponseType.CANCEL)
        dialog.add_button('Valider', Gtk.ResponseType.OK)
        dialog.set_default_response(Gtk.ResponseType.OK)
        area = dialog.get_content_area()
        area.set_spacing(10)
        area.set_margin_start(16); area.set_margin_end(16); area.set_margin_top(12)
        area.add(Gtk.Label(label="Comment tu t'appelles ?"))
        entry = Gtk.Entry()
        entry.set_text(self.user_name)
        entry.set_activates_default(True)
        area.add(entry)
        dialog.show_all()
        if dialog.run() == Gtk.ResponseType.OK:
            name = entry.get_text().strip()
            self.user_name = name
            write_cfg(NAME_CONFIG, name)
            self._refresh_greeting()
            self._refresh_name_btn()
            # GECOS + restart panel hors thread UI (apply_user_name ne capture
            # aucun tuyau → pas de gel). Dans un thread pour rester fluide.
            threading.Thread(target=apply_user_name, args=(self.env,),
                             daemon=True).start()
        dialog.destroy()

    def _has_unsaved(self):
        return (self.sel_profile    != self.saved_profile or
                self.sel_font_style != self.saved_font_style or
                self.sel_font_size  != self.saved_font_size or
                self.sel_cursor_sz  != self.saved_cursor_sz)

    # Style
    def _on_card_click(self, widget, event, key):
        for k, card in self.profile_cards.items():
            ctx = card.get_style_context()
            ctx.add_class('active') if k == key else ctx.remove_class('active')
        self.sel_profile = key

    # Police
    def _on_font_card_click(self, widget, event, key):
        for k, card in self.font_cards.items():
            ctx = card.get_style_context()
            ctx.add_class('active') if k == key else ctx.remove_class('active')
        self.sel_font_style = key

    def _on_font_size(self, btn, size):
        for sz, b in self.size_btns.items():
            ctx = b.get_style_context()
            ctx.add_class('active') if sz == size else ctx.remove_class('active')
        self.sel_font_size = size

    def _on_cursor_size(self, btn, size):
        for sz, b in self.cursor_btns.items():
            ctx = b.get_style_context()
            ctx.add_class('active') if sz == size else ctx.remove_class('active')
        self.sel_cursor_sz = size

    def _on_apply_all(self, btn):
        changed_icons  = self.sel_profile    != self.saved_profile
        changed_font   = (self.sel_font_style != self.saved_font_style or
                          self.sel_font_size  != self.saved_font_size)
        changed_cursor = self.sel_cursor_sz  != self.saved_cursor_sz

        if not (changed_icons or changed_font or changed_cursor):
            d = Gtk.MessageDialog(parent=self, flags=0,
                                  message_type=Gtk.MessageType.INFO,
                                  buttons=Gtk.ButtonsType.OK,
                                  text='Aucun changement à appliquer.')
            d.run(); d.destroy()
            return

        # On applique DANS UN THREAD : session-init + relance xfdesktop
        # prennent ~2 s. Bloquer le thread GTK = fenêtre figée (bug 12/06).
        # Snapshot des sélections (le thread ne touche jamais un widget).
        prof, fstyle = self.sel_profile, self.sel_font_style
        fsize, csz   = self.sel_font_size, self.sel_cursor_sz
        self.apply_btn.set_sensitive(False)
        self.apply_btn.set_label('Application en cours…')

        def worker():
            if changed_font or changed_cursor:
                apply_reading(fstyle, fsize, self.env)
                apply_cursor(csz, self.env)
            if changed_icons:
                apply_profile(prof, self.env)
            GLib.idle_add(self._apply_done, changed_icons, changed_font,
                          changed_cursor, prof, fstyle, fsize, csz)

        threading.Thread(target=worker, daemon=True).start()

    def _apply_done(self, changed_icons, changed_font, changed_cursor,
                    prof, fstyle, fsize, csz):
        """Repris sur le thread GTK (via idle_add) une fois l'apply fini :
        on met à jour l'état sauvegardé et on réactive le bouton. Pas de
        popup ni de fermeture — l'effet est visible à l'écran (retour
        Florent), l'app reste ouverte pour essayer d'autres styles."""
        if changed_font or changed_cursor:
            self.saved_font_style = fstyle
            self.saved_font_size  = fsize
            self.saved_cursor_sz  = csz
        if changed_icons:
            self.saved_profile = prof
        self.apply_btn.set_sensitive(True)
        self.apply_btn.set_label('✅  Appliquer les changements')
        return False  # one-shot idle

    def _on_close(self, widget, event):
        if not self._has_unsaved():
            return False  # ferme normalement
        dialog = Gtk.Dialog(title='Changements non appliqués', parent=self, flags=0)
        dialog.add_button('Quitter sans appliquer', Gtk.ResponseType.REJECT)
        dialog.add_button('Annuler', Gtk.ResponseType.CANCEL)
        ok = dialog.add_button('Appliquer', Gtk.ResponseType.OK)
        ok.get_style_context().add_class('primary-btn')
        area = dialog.get_content_area()
        area.set_margin_start(16); area.set_margin_end(16)
        area.set_margin_top(12); area.set_margin_bottom(8)
        area.add(Gtk.Label(
            label='Des changements ne sont pas encore appliqués.\nVoulez-vous les appliquer avant de fermer ?'))
        dialog.show_all()
        response = dialog.run()
        dialog.destroy()
        if response == Gtk.ResponseType.OK:
            self._on_apply_all(None)   # apply asynchrone (~2 s)
            return True  # garde la fenêtre le temps d'appliquer ; refermer ensuite
        elif response == Gtk.ResponseType.REJECT:
            return False  # quitte sans appliquer
        return True  # annule la fermeture

    def _on_show_guide(self, btn):
        subprocess.Popen(['firefox', f'file://{GUIDES_INDEX}'], env=self.env)

    # ------------------------------------------------------------------ #
    # Events — accès espace parent                                         #
    # ------------------------------------------------------------------ #
    def _on_parent_click(self, btn):
        if not has_pin():
            self._ask_create_pin()
        else:
            self._ask_pin()

    def _ask_create_pin(self):
        dialog = Gtk.Dialog(title='Créer un code parent', parent=self, flags=0)
        dialog.set_default_size(340, 170)
        dialog.add_button('Plus tard', Gtk.ResponseType.CANCEL)
        dialog.add_button('Créer', Gtk.ResponseType.OK).get_style_context().add_class('primary-btn')
        dialog.set_default_response(Gtk.ResponseType.OK)
        area = dialog.get_content_area()
        area.set_spacing(10)
        area.set_margin_start(16); area.set_margin_end(16); area.set_margin_top(12)
        area.add(Gtk.Label(label='Protégez l\'espace parent avec un code à 4 chiffres.'))
        e1 = Gtk.Entry()
        e1.set_placeholder_text('Code à 4 chiffres')
        e1.set_visibility(False); e1.set_max_length(4)
        e1.set_input_purpose(Gtk.InputPurpose.DIGITS)
        e1.connect('changed', lambda w: e2.grab_focus() if len(w.get_text()) == 4 else None)
        area.add(e1)
        e2 = Gtk.Entry()
        e2.set_placeholder_text('Confirmer le code')
        e2.set_visibility(False); e2.set_max_length(4)
        e2.set_input_purpose(Gtk.InputPurpose.DIGITS)
        e2.set_activates_default(True)
        area.add(e2)
        err_lbl = Gtk.Label(label='')
        err_lbl.get_style_context().add_class('sub')
        area.add(err_lbl)
        dialog.show_all()
        while True:
            response = dialog.run()
            if response != Gtk.ResponseType.OK:
                dialog.destroy()
                self.stack.set_visible_child_name('parent')
                return
            p1, p2 = e1.get_text().strip(), e2.get_text().strip()
            if len(p1) != 4 or not p1.isdigit():
                err_lbl.set_text('⚠ Le code doit contenir exactement 4 chiffres.')
                e1.set_text(''); e2.set_text('')
                continue
            if p1 != p2:
                err_lbl.set_text('⚠ Les codes ne correspondent pas.')
                e2.set_text('')
                continue
            write_cfg(PIN_CONFIG, pin_hash(p1))
            break
        dialog.destroy()
        self.stack.set_visible_child_name('parent')

    def _ask_pin(self):
        dialog = Gtk.Dialog(title='Code parent', parent=self, flags=0)
        dialog.set_default_size(300, 120)
        dialog.add_button('Annuler', Gtk.ResponseType.CANCEL)
        dialog.add_button('Valider', Gtk.ResponseType.OK).get_style_context().add_class('primary-btn')
        dialog.set_default_response(Gtk.ResponseType.OK)
        area = dialog.get_content_area()
        area.set_spacing(10)
        area.set_margin_start(16); area.set_margin_end(16); area.set_margin_top(12)
        msg = Gtk.Label(label='Code parent (4 chiffres) :')
        area.add(msg)
        entry = Gtk.Entry()
        entry.set_visibility(False); entry.set_max_length(4)
        entry.set_input_purpose(Gtk.InputPurpose.DIGITS)
        entry.set_activates_default(True)
        area.add(entry)
        attempts = [0]
        dialog.show_all()
        while True:
            response = dialog.run()
            if response != Gtk.ResponseType.OK:
                dialog.destroy(); return
            if check_pin(entry.get_text().strip()):
                break
            attempts[0] += 1
            entry.set_text('')
            s = 's' if attempts[0] > 1 else ''
            msg.set_text(f'Code incorrect ({attempts[0]} essai{s}). Réessayez :')
        dialog.destroy()
        self.stack.set_visible_child_name('parent')

    # ------------------------------------------------------------------ #
    # Events — espace parent                                               #
    # ------------------------------------------------------------------ #
    def _on_update(self, btn):
        btn.set_sensitive(False)
        btn.set_label('En cours…')
        while Gtk.events_pending():
            Gtk.main_iteration()
        try:
            # Autorisé par la règle polkit dédiée (modules/ota-installed.nix)
            proc = subprocess.run(
                ['systemctl', 'start', 'apprendys-ota.service'],
                env=self.env, capture_output=True, text=True, timeout=600)
            msg = 'Vérification terminée.\nSi une mise à jour a été installée, elle sera active au prochain démarrage.' \
                if proc.returncode == 0 \
                else 'Impossible de lancer la mise à jour.\n(vérifiez la connexion internet)'
        except subprocess.TimeoutExpired:
            msg = 'La mise à jour prend du temps — elle continue en arrière-plan.'
        except Exception as e:
            msg = f'Erreur : {e}'
        btn.set_sensitive(True)
        btn.set_label('Vérifier maintenant')
        d = Gtk.MessageDialog(parent=self, flags=0,
                              message_type=Gtk.MessageType.INFO,
                              buttons=Gtk.ButtonsType.OK, text=msg)
        d.run(); d.destroy()


if __name__ == '__main__':
    app = MonApprendys()
    app.show_all()
    Gtk.main()
