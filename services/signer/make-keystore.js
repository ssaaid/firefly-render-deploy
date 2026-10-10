const { Wallet } = require("ethers");
const fs = require("fs");
const path = require("path");

const [, , privateKey, keystoreDir] = process.argv;

(async () => {
  const wallet = new Wallet(privateKey);
  const password = "firefly";
  const json = await wallet.encrypt(password);
  // Must match fileWallet.filenames.primaryExt/passwordExt in
  // ffsigner.yml.template. With passwordExt left unset, ffsigner looks for
  // the password in a file with the SAME name as the key file -- i.e. the
  // key file itself -- and "decrypts" using the encrypted JSON as the
  // password (always wrong) before ever reaching defaultPasswordFile.
  const address = wallet.address.slice(2).toLowerCase();
  fs.writeFileSync(path.join(keystoreDir, `${address}.key.json`), json);
  fs.writeFileSync(path.join(keystoreDir, `${address}.pwd`), password);
  console.error(`Generated keystore for address ${wallet.address}`);
})();
