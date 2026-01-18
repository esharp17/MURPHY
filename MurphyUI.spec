# -*- mode: python ; coding: utf-8 -*-

block_cipher = None


a = Analysis(
    ['ui_qml/main.py'],
    pathex=['C:/py/murphy'],
    binaries=[],
    datas=[
        ('ui_qml/RobotUI', 'RobotUI'),
    ],
    hiddenimports=[],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)


pyz = PYZ(
    a.pure,
    a.zipped_data,
    cipher=block_cipher,
)


exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name='MurphyUI',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
