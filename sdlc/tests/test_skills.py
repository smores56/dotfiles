"""Validation for the agent skills shipped in `skills/`.

Every agent loads `skills/*/SKILL.md` by frontmatter, so a malformed file
silently costs it a phase.
"""

import os
import unittest

SKILLS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "skills")

REQUIRED_SKILLS = {
    "sdlc",
    "research",
    "design-brainstorm",
    "grill-me",
    "review",
    "test-driven-development",
    "resolve-pr",
}

REQUIRED_KEYS = ("name", "description")


def skill_paths():
    if not os.path.isdir(SKILLS_DIR):
        return []
    return sorted(
        os.path.join(SKILLS_DIR, name, "SKILL.md")
        for name in os.listdir(SKILLS_DIR)
        if os.path.isfile(os.path.join(SKILLS_DIR, name, "SKILL.md"))
    )


def split_frontmatter(text):
    """Return (keys, body) for a leading `---` block, or (None, text)."""
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return None, text
    for index, line in enumerate(lines[1:], start=1):
        if line.strip() == "---":
            return lines[1:index], "\n".join(lines[index + 1 :])
    return None, text


def frontmatter_keys(lines):
    """Top-level `key: value` pairs; indented and nested lines are ignored."""
    keys = {}
    for line in lines:
        if not line or line[0].isspace() or ":" not in line:
            continue
        key, value = line.split(":", 1)
        keys[key.strip()] = value.strip()
    return keys


class SkillFrontmatterTest(unittest.TestCase):
    def test_skills_directory_exists(self):
        self.assertTrue(os.path.isdir(SKILLS_DIR), "skills/ is missing")

    def test_required_skills_are_present(self):
        present = {
            os.path.basename(os.path.dirname(path))
            for path in skill_paths()
        }
        self.assertEqual(REQUIRED_SKILLS - present, set(), "missing SKILL.md files")

    def test_every_skill_has_frontmatter_and_body(self):
        paths = skill_paths()
        self.assertTrue(paths, "no skills/*/SKILL.md found")
        for path in paths:
            name = os.path.basename(os.path.dirname(path))
            with self.subTest(skill=name):
                with open(path, encoding="utf-8") as handle:
                    text = handle.read()
                lines, body = split_frontmatter(text)
                self.assertIsNotNone(
                    lines, "%s: no `---` delimited frontmatter block" % path
                )
                keys = frontmatter_keys(lines)
                for key in REQUIRED_KEYS:
                    self.assertIn(key, keys, "%s: frontmatter lacks %r" % (path, key))
                    self.assertTrue(
                        keys[key], "%s: frontmatter %r is empty" % (path, key)
                    )
                self.assertEqual(
                    keys["name"],
                    name,
                    "%s: frontmatter name must match the directory" % path,
                )
                self.assertFalse(
                    any("\n" in value for value in keys.values()),
                    "%s: frontmatter values must be single lines" % path,
                )
                body_lines = [line for line in body.splitlines() if line.strip()]
                self.assertTrue(body_lines, "%s: body is empty" % path)
                self.assertTrue(
                    body_lines[0].startswith("# "),
                    "%s: body must open with a markdown heading" % path,
                )


if __name__ == "__main__":
    unittest.main()
