// Brand configuration. Replace placeholders with official DigiCert values.
// Logo files live in /public/brand/ and are referenced by path so you can swap
// them without touching code.
export const brand = {
  productName: "DDR Console",           // TODO(brand): official product name
  company: "DigiCert",                  // TODO(brand): confirm wordmark usage
  // TODO(brand): drop official SVGs into web/public/brand/ with these names.
  logoFull: "/brand/digicert-logo.svg", // horizontal lockup for the top bar
  logoMark: "/brand/digicert-mark.svg", // square mark for collapsed/mobile
  // The org shown in the header — will be replaced by live data from the API.
  defaultOrg: "Vercara — Demo Sandbox",
  supportUrl: "https://www.digicert.com/support", // TODO(brand): confirm
};
