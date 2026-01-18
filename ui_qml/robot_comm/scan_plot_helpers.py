import os
from ftplib import FTP

# You already have these globals somewhere; don’t rely on that.
# Make them arguments instead.

def fetch_offsets_xml_from_robot(robot_ip: str, ftp_user: str, ftp_pass: str, base_dir: str) -> str:
    local_path = os.path.join(base_dir, "offsets.xml")

    ftp = FTP()
    ftp.connect(robot_ip, 21, timeout=5)
    ftp.login(user=ftp_user, passwd=ftp_pass)

    cwd_ok = False
    for path in ("FR:\\", "FR:", "fr"):
        try:
            ftp.cwd(path)
            cwd_ok = True
            break
        except Exception:
            pass

    remote_name = "OFFSETS.XML"
    with open(local_path, "wb") as f:
        ftp.retrbinary("RETR " + remote_name, f.write)

    ftp.quit()
    return local_path


def normalize_offsets_xml(local_path: str, base_dir: str) -> str:
    norm_path = os.path.join(base_dir, "offsets_norm.xml")

    with open(local_path, "r", encoding="utf-8", errors="ignore") as f:
        raw = f.read().strip()

    if raw.startswith("<?xml") and ("<offset_log" in raw) and ("</offset_log>" in raw):
        with open(norm_path, "w", encoding="utf-8") as out:
            out.write(raw)
        return norm_path

    rows = []
    for line in raw.splitlines():
        s = line.strip()
        if s.startswith("<row") and s.endswith("/>"):
            rows.append(s)

    with open(norm_path, "w", encoding="utf-8") as out:
        out.write('<?xml version="1.0"?>\n')
        out.write("<offset_log>\n")
        for r in rows:
            out.write("  " + r + "\n")
        out.write("</offset_log>\n")

    return norm_path
