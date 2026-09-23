from pathlib import Path
import subprocess

source = Path('scripts/.checkless_source.py')
text = source.read_text()
start = text.index('# Fork integration must not restart')
end = text.index("p=root/'ReadMe.md'", start)
# Workflow relocation is already committed by the authorized GitHub connector.
# The runner only commits application source/docs/tests, not workflow changes.
exec(compile(text[:start] + text[end:], str(source), 'exec'))
p = Path('tests/test_gitee_checkless.py')
s = p.read_text()
old = '''            self.assertIn("github.repository == 'Ebullioscopic/Atoll'",(ROOT/'.github/workflows'/name).read_text())'''
new = '''            self.assertFalse((ROOT/'.github/workflows'/name).exists())
            self.assertTrue((ROOT/'docs/upstream-workflows'/name).exists())'''
assert old in s
p.write_text(s.replace(old, new))
p = Path('TOOLISLE-GITEE-CHECKLESS.md')
s = p.read_text().replace('旧上游 CI/发布/镜像/nightly/命令自动化仅允许在上游运行，避免合并到 dev 后意外发布或修改其他分支。', '旧上游 CI/发布/镜像/nightly/命令自动化已原样归档到 docs/upstream-workflows，不随 dev 合并重新启用，避免意外发布或修改其他分支。')
p.write_text(s)
subprocess.run(['git','rm',str(source)],check=True)
