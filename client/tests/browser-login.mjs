const password = 'CASQA-local-2026';

export async function signInLocal(page, user, register = false) {
  const button = (name) => page.getByRole('button', { name, exact: true });
  if (register) await button('新用户，创建账号').click();
  await page.getByLabel('用户名').fill(user);
  await page.getByLabel('密码').fill(password);
  await button(register ? '注册并进入母港' : '登录并进入母港').click();
  await page.locator('.growth-port').waitFor();
}

export async function resumeExercise(page) {
  const button = (name) => page.getByRole('button', { name, exact: true });
  await button('打开主菜单').click();
  await button('继续演习').click();
  await page.locator('.battle-map').waitFor();
}

export async function openAcademy(page) {
  await page.locator('.growth-lesson').click();
  await page.getByRole('navigation', { name: '母港区域' }).getByRole('button', { name: '舰桥学堂', exact: true }).waitFor();
}
