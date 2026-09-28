#!/usr/bin/env python3
"""Session digest for a skill retrospective: skills used, user messages, the assistant's own
narration (where failures inside successful commands get described), and failed tool calls.

  digest.py [transcript.jsonl]

Without an argument, reads the newest transcript for the current directory under
~/.claude/projects/. Prints one line per event, in order, so the friction in a long session
can be read in a few screens even after the conversation context was compacted.
"""
import glob, json, os, re, sys

NOISE = re.compile(r"<(system-reminder|local-command-caveat|local-command-stdout)>.*?</\1>", re.S)
SKILL_BODY = "Base directory for this skill:"  # a loaded skill's full text, already shown as SKILL


def transcript():
    if len(sys.argv) > 1:
        return sys.argv[1]
    project = os.path.expanduser("~/.claude/projects/" + re.sub(r"[^A-Za-z0-9-]", "-", os.getcwd()))
    files = sorted(glob.glob(f"{project}/*.jsonl"), key=os.path.getmtime)
    if not files:
        sys.exit(f"no transcripts in {project}")
    return files[-1]


def one_line(text, limit=220):
    text = " ".join(text.split())
    return text if len(text) <= limit else text[:limit] + "…"


def main():
    tools, skills = {}, []
    for n, raw in enumerate(open(transcript()), 1):
        d = json.loads(raw)
        kind, msg = d.get("type"), d.get("message") or {}
        content = msg.get("content")
        if kind == "assistant" and isinstance(content, list):
            skill = d.get("attributionSkill")
            if skill and skill not in skills:
                skills.append(skill)
                print(f"{n:>6} SKILL   {skill}")
            for block in content:
                if block.get("type") == "text" and block["text"].strip() and not d.get("isSidechain"):
                    print(f"{n:>6} NOTE    {one_line(block['text'])}")
                if block.get("type") == "tool_use":
                    args = block.get("input") or {}
                    tools[block["id"]] = f"{block['name']}: {args.get('description') or args.get('file_path') or args.get('skill') or ''}"
        if kind != "user" or d.get("isSidechain"):
            continue
        if isinstance(content, str):
            text = NOISE.sub("", content).strip()
            if text and not text.startswith(SKILL_BODY):
                print(f"{n:>6} USER    {one_line(text)}")
            continue
        for block in content or []:
            if block.get("type") == "text":
                text = NOISE.sub("", block["text"]).strip()
                if text and not text.startswith(SKILL_BODY):
                    print(f"{n:>6} USER    {one_line(text)}")
            elif block.get("type") == "tool_result" and block.get("is_error"):
                body = block.get("content")
                if isinstance(body, list):
                    body = " ".join(b.get("text", "") for b in body if isinstance(b, dict))
                print(f"{n:>6} ERROR   [{tools.get(block.get('tool_use_id'), '?')}] {one_line(str(body), 160)}")


if __name__ == "__main__":
    main()
