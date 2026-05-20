# Terms of Service — Phalanx Foundation

> **Status**: Pre-launch draft. Effective date will be set when the Toolkit launches publicly. The current text reflects the policy framework; jurisdictional details (Section 13) require legal review prior to public launch.

**Effective date**: TBD (will be set on the day this document is first published publicly).

Last updated: 2026-05-20

---

## 1. Acceptance of Terms

By accessing the websites, smart contracts, software, or services published by Phalanx Foundation (collectively, the "**Services**"), or by holding the PLX token, you ("**you**", "**Customer**", or "**User**") agree to be bound by these Terms of Service ("**Terms**"). If you do not agree to these Terms, do not use the Services.

These Terms apply to:

- The PLX token contract and any contracts published in the `phalanx-foundation/plx-token` repository.
- The Phalanx Tokenization Toolkit (the "**Toolkit**"), once launched, including its web interface, API, smart-contract templates, and analytics dashboards.
- Any other software, content, or service offered by Phalanx Foundation in the future.

We may update these Terms from time to time. The current version will always be available at the published URL with a visible "last updated" date. Material changes will be announced on our public Telegram channel at least 14 days before they take effect, and continued use of the Services after that period constitutes acceptance.

---

## 2. Description of Services

Phalanx Foundation provides:

1. **Open-source smart contracts** under MIT licence in our public GitHub repositories. Anyone may read, fork, audit, modify, and deploy these contracts. Use of the open-source contracts as published does not require a commercial agreement with Phalanx Foundation.
2. **The Tokenization Toolkit** — a self-service web application that orchestrates the deployment of Phalanx-authored smart-contract templates to the TON blockchain on a Customer's behalf, in exchange for a fee.
3. **Hosted analytics, dashboards, and operational tooling** for tokens deployed through the Toolkit, provided as a subscription service.

---

## 3. The Customer Is the Issuer

When you use the Toolkit to deploy a token, **you are the issuer of that token**. You are solely responsible for:

- The legality of issuing a token in your jurisdiction and in the jurisdictions of your purchasers.
- Whether your token is classified as a security, utility token, or otherwise under applicable law.
- KYC, AML, sanctions screening, tax reporting, consumer protection, and any other compliance obligation arising from your token issuance and any subsequent sale, distribution, or marketing of your token.
- The truthfulness and accuracy of every claim you make about your token, including in the metadata, marketing material, social channels, and any communications with purchasers or holders.
- Disputes with purchasers or holders of your token.

Phalanx Foundation provides **tooling**. We do not market your token, do not custody your customers' funds, do not vouch for the value or legitimacy of your token, and do not assume any duty toward purchasers of your token. Phalanx Foundation is to your token issuance what AWS is to any application running on it.

---

## 4. Toolchain & Third-Party Dependency Disclaimer

The Toolkit builds and deploys smart contracts using the open-source **Tolk** language and the open-source **Acton** toolchain, both maintained by the wider TON ecosystem and not controlled by Phalanx Foundation. Deployments rely on the **TON blockchain** itself, on **third-party RPC providers**, on **decentralised exchanges** (Ston.fi, DeDust, etc.) for any liquidity actions, and on **third-party wallet software** (Tonkeeper, etc.) for end-user interaction.

You acknowledge and agree that:

- A previously unknown defect, regression, or breaking change in Tolk, Acton, the TON virtual machine, any third-party RPC, any third-party DEX, or any third-party wallet may affect contracts deployed through the Toolkit, including potential loss, freeze, or burn of tokens or TON.
- **Phalanx Foundation is not liable for any loss, damage, freeze, theft, fork, or unavailability arising from a defect in any third-party tool or service**, including but not limited to Tolk, Acton, TON RPC providers, TON itself, DEXes, wallets, or operating-system level vulnerabilities of devices used by you or your customers.
- We test extensively against current versions of these tools and will publish advisories if a defect is discovered, but our liability is strictly limited as set out in Section 11 (Limitation of Liability).

---

## 5. Pricing, Payment, and Refunds

### 5.1 Fees

The Toolkit operates on a tiered pricing model published at `phalanx.foundation/pricing` and reproduced in our public documentation. All fees are denominated in TON or in fiat-equivalents at the rate quoted at the time of purchase.

Each tier consists of:

- A **one-time deployment fee**, payable before the smart-contract deployment is queued.
- A **recurring monthly subscription fee**, payable in advance, that covers ongoing hosted services (analytics, dashboard, customer-token landing page, support, alerting).

Customers paying with PLX receive a published discount on the deployment fee. Discounts are not retroactive.

### 5.2 Supported Payment Methods

We accept payment in any of the following at the Customer's choice:

- **Stripe** (cards, Apple Pay, Google Pay, regional methods supported by Stripe in the Customer's jurisdiction).
- **PayPal**.
- **USDT** (TRC-20, ERC-20, TON-Jetton form, BEP-20).
- **BTC** (on-chain Bitcoin).
- **ETH** (mainnet Ethereum).
- **TON** (native TON Coin).
- **PLX** (Phalanx Foundation Jetton on TON, with the published discount applied).

We reserve the right to add, remove, or change payment processors at any time, with reasonable notice on the public pricing page. Where a payment processor's terms conflict with these Terms (for example, Stripe's mandatory dispute procedures), the processor's terms control for the limited purpose of payment processing.

### 5.3 No Refunds

**All payments are final and non-refundable** once the corresponding service has been rendered. For the avoidance of doubt:

- The deployment fee is rendered as soon as the smart-contract deployment transaction is broadcast to the TON network, regardless of whether the Customer subsequently changes their mind, encounters an exchange listing problem, or fails to attract end-user demand for the deployed token.
- The monthly subscription fee covers a calendar month of hosted services. Cancellation mid-month does not produce a partial refund; the Customer retains access to the hosted services through the end of the paid month.
- Crypto-denominated payments are refundable only in the event of an obvious double-charge or technical failure on our side, and only to the same wallet address that originated the payment, at our sole discretion.

### 5.4 Failed Payments and Service Suspension

If a recurring subscription payment fails or is not received by its due date, hosted services for the affected Customer will be progressively wound down according to the schedule published in the Cancellation & Suspension Policy at `phalanx.foundation/legal/suspension`, which forms part of these Terms by reference.

---

## 6. The Smart Contracts Belong to the Customer

Once a smart contract is deployed through the Toolkit, **the Customer is the sole owner of that contract on the TON blockchain**. The contract's `admin` is set to a wallet under the Customer's control. Phalanx Foundation cannot subsequently:

- Mint, burn, transfer, or otherwise move the Customer's tokens.
- Modify the Customer's contract code.
- Recover access to a wallet whose seed phrase the Customer has lost.
- "De-list" or "shut down" a deployed contract — once on-chain, contracts run autonomously and continue to function regardless of the Customer's relationship with Phalanx Foundation.

If the Customer ceases to pay subscription fees, Phalanx Foundation will only stop providing **hosted services** (analytics dashboard, hosted token landing page, support, alerting, subdomain routing). The on-chain smart contracts and the Customer's token continue to function autonomously and the Customer may continue to interact with them via Tonviewer, third-party wallets, or any other tool.

---

## 7. Acceptable Use

You agree not to use the Services to:

- Issue or facilitate the issuance of any token whose name, symbol, or metadata infringes on a registered trademark you do not own.
- Issue any token whose name, symbol, or metadata impersonates or is reasonably likely to be confused with a public figure, government program, or major brand without that party's permission.
- Issue any token in violation of applicable sanctions, AML, securities, gambling, consumer-protection, or fraud laws.
- Use the Services to defraud purchasers or holders of any token.
- Attack, probe, or otherwise interfere with the Services beyond legitimate testing of your own deployment.

We reserve the right to reject a deployment request, suspend hosted services, and refuse refunds if we have a reasonable belief that the Customer is in breach of this Section. Smart contracts already deployed at the time of breach remain on-chain and outside our control, as described in Section 6.

---

## 8. Intellectual Property

- The smart-contract source code published in the `phalanx-foundation/plx-token` repository (and any other repository so designated) is licensed under the MIT licence and may be used by anyone in accordance with that licence.
- The web application, dashboards, branding (including the **Phalanx Foundation** name and Spartan-helmet visual identity), and any non-public source code are the exclusive property of Phalanx Foundation. Use of the brand, logo, or non-public code without written permission is prohibited.
- Customers retain all rights in the metadata, branding, and content they upload to the Toolkit. By uploading, the Customer grants Phalanx Foundation a non-exclusive, worldwide, royalty-free licence to host, display, and process that content solely as needed to provide the Services.

---

## 9. Privacy

Our handling of personal data is described in our Privacy Policy at `phalanx.foundation/legal/privacy`, which forms part of these Terms by reference. In summary:

- We collect the minimum data necessary to provide the Services (account email, billing identifiers, IP for fraud-prevention).
- We do not sell personal data to third parties.
- We retain audit logs of significant operational events for legal-compliance and security reasons.
- We do not custody seed phrases, private keys, or passphrases at any time.

---

## 10. Indemnification

You agree to indemnify, defend, and hold harmless Phalanx Foundation, its contributors, agents, and affiliates from and against any and all claims, damages, losses, liabilities, costs, and expenses (including reasonable legal fees) arising from or related to:

- Your token issuance, marketing, sale, distribution, or operation.
- Your breach of these Terms or any applicable law.
- Any dispute with a purchaser, holder, or third party concerning your token.

---

## 11. Limitation of Liability

To the maximum extent permitted by applicable law:

- The Services are provided **"AS IS" and "AS AVAILABLE"** without warranty of any kind, express or implied, including but not limited to merchantability, fitness for a particular purpose, non-infringement, accuracy, reliability, security, or availability.
- Phalanx Foundation, its contributors, agents, and affiliates **shall not be liable** for any indirect, incidental, special, consequential, exemplary, or punitive damages, including but not limited to lost profits, lost tokens, lost data, lost revenue, business interruption, loss of goodwill, or any damages arising from third-party tool defects (Section 4), TON network conditions, DEX behaviour, wallet behaviour, or your own operational mistakes.
- The aggregate liability of Phalanx Foundation to any Customer for any cause whatsoever and regardless of the form of the action shall be limited to **the lesser of: (a) the total fees actually paid by that Customer to Phalanx Foundation in the three (3) months immediately preceding the event giving rise to the claim, or (b) one hundred U.S. dollars (USD 100)**.
- Some jurisdictions do not allow the exclusion of certain warranties or the limitation of certain damages; in such jurisdictions our liability is limited to the maximum extent permitted by law.

---

## 12. Termination

You may stop using the Services at any time. We may terminate or suspend your access to the Services immediately, without notice, if you breach these Terms, fail to pay fees due, or use the Services in violation of any applicable law. Termination of the Services does not affect the on-chain status of your already-deployed smart contracts (see Section 6).

Sections 3, 4, 5.3, 6, 8, 10, 11, 12, and 13 survive termination.

---

## 13. Governing Law and Dispute Resolution

These Terms are governed by the laws of TBD (jurisdiction to be selected before public publication, on advice of counsel). Any dispute arising from or relating to these Terms or the Services shall be resolved through:

1. **Good-faith negotiation** via written notice for at least 30 days, followed by
2. **Binding arbitration** under TBD arbitral rules, in TBD city, with one arbitrator and proceedings in English. The arbitrator's award shall be final and enforceable in any court of competent jurisdiction.

You and Phalanx Foundation each waive any right to bring any claim as a class, representative, or collective action.

---

## 14. Miscellaneous

- **Severability**. If any provision of these Terms is held unenforceable, the remaining provisions remain in full force.
- **No waiver**. Failure by Phalanx Foundation to enforce any right is not a waiver of that right.
- **Assignment**. You may not assign these Terms without our written consent. We may assign these Terms to a successor entity (for example, a community-controlled foundation in line with our governance roadmap) on notice to you.
- **Entire agreement**. These Terms, together with the Privacy Policy and the Cancellation & Suspension Policy, constitute the entire agreement between you and Phalanx Foundation regarding the Services.

---

## Implementation checklist before public publication

- [ ] Review by qualified legal counsel in the chosen governing-law jurisdiction.
- [ ] Fill in `Section 13` jurisdiction, arbitral seat, and arbitral rules with counsel's recommendation.
- [ ] Set the actual effective date in the header.
- [ ] Publish at `phalanx.foundation/legal/terms` and link from website footer + Toolkit signup flow.
- [ ] Publish referenced sub-policies (`/legal/privacy`, `/legal/suspension`).
- [ ] Add a banner on the Toolkit signup that says "By creating an account you agree to the Terms of Service" with hyperlink.
- [ ] Sign each public revision with the Foundation's GPG key for tamper-evidence; store signature alongside the published file.
