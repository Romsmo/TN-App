/** Creates the mock server's first instance (`/i/1`): the one the test build of the app is wired to. */
export default async function globalSetup(): Promise<void> {
  const response = await fetch('http://127.0.0.1:18990/__instances', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ cameraNamespace: true, cameraPolicy: { defaultLevel: 'full', byCountry: {}, namespaceEnabled: true }, cameraData: { camera: true }, communityCorrections: true }),
  });
  const { url } = (await response.json()) as { url: string };
  if (!url.endsWith('/i/1')) throw new Error(`the test build is wired to /i/1, the mock server answered ${url}: restart it`);
}
