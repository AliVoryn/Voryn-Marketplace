# گزارش اصلاحات پروژه‌ی پروتکل

این فایل تمام تغییراتی که روی کد اعمال شد رو مستند می‌کنه. **هیچ منطق تجاری (business logic) جایی تغییر نکرده** — یعنی نحوه‌ی محاسبه‌ی قیمت حراج هلندی، فرمول پاداش استیکینگ، قوانین fee، جریان mint/burn توکن، منطق فازهای حراج و... همه دقیقاً همونیه که بود. فقط جاهایی که کد کامپایل نمی‌شد، جای امنیتی خطر داشت، حساب‌ها اشتباه می‌شد، یا کد عیناً تکراری بود، دست خورده.

---

## ۱) باگ‌های کامپایل‌شکن (Compile-breaking)

### 1.1 `IFactory.sol` ↔ `ProtocolFactory.sol` — امضای ناسازگار
- **مشکل:** `createBlindAuctionInstance` توی اینترفیس ۵ پارامتر داشت، توی پیاده‌سازی با `override` و ۹ پارامتر تعریف شده بود.
- **اصلاح:** اینترفیس با پیاده‌سازی (که منطق کامل‌تری داشت) هماهنگ شد. تابع `predictCustomNFTAddress` هم به اینترفیس اضافه شد چون بخشی از API عمومی بود ولی در اینترفیس نبود.
- **فایل‌ها:** `interfaces/IFactory.sol`, `factory/ProtocolFactory.sol`

### 1.2 `DutchAuction.sol` — کلمه‌ی `override` جا افتاده بود (۷ مورد)
- **مشکل:** توابع `createAuction`, `buy`, `cancelAuction`, `expireAuction`, `currentPrice`, `getAuction`, `auctionCount` همگی از `IDutchAuction` پیاده‌سازی می‌شدن ولی `override` نداشتن → خطای کامپایل «Overriding function is missing 'override' specifier».
- **اصلاح:** `override` به هر ۷ تابع اضافه شد.
- **فایل:** `core/DutchAuction.sol`

### 1.3 `Marketplace.sol` — `invalidateNonce()` بدون `override`
- **مشکل:** `IMarketplace` این تابع رو تعریف کرده بود، پیاده‌سازی `override` نداشت.
- **اصلاح:** `override` اضافه شد.
- **فایل:** `core/Marketplace.sol`

### 1.4 `Treasury.sol` — `setAuthorizedPayer()` بدون `override`
- **مشکل:** مشابه بالا، `ITreasury` این تابع رو تعریف کرده بود ولی پیاده‌سازی `override` نداشت.
- **اصلاح:** `override` اضافه شد.
- **فایل:** `core/Treasury.sol`

### 1.5 `ProtocolFactory.sol` — `predictCustomNFTAddress` بدون `override`
- بعد از اضافه شدن این تابع به `IFactory` (بند ۱.۱)، پیاده‌سازی هم باید `override` می‌گرفت.
- **فایل:** `factory/ProtocolFactory.sol`

---

## ۲) باگ امنیتی (Security)

### 2.1 `ProtocolFactory.createBlindAuctionInstance` — عدم احراز هویت فراخوان
- **مشکل:** تابع پارامتر `beneficiary` (صاحب NFT) رو جدا از `msg.sender` می‌گرفت و NFT رو مستقیماً با `transferFrom(beneficiary, ...)` پول می‌کرد، بدون چک اینکه فراخوان‌کننده واقعاً همون `beneficiary` باشه. یعنی هر کسی که `beneficiary` قبلاً به فکتوری approve عمومی داده بود (برای هر منظور دیگه‌ای)، می‌تونست NFTِ اون رو بدون اجازه‌ی صریح وارد یه حراج کور با شرایط دلخواه خودش کنه (مثلاً `reservePrice = 0`).
- **اصلاح:** چک `if (msg.sender != beneficiary) revert NotSeller();` اضافه شد — دقیقاً هم‌راستا با الگویی که همه‌ی توابع مشابه دیگه (OpenAuction.createAuction، DutchAuction.createAuction، Marketplace.acceptOffer) از قبل رعایت می‌کردن.
- **فایل:** `factory/ProtocolFactory.sol`

---

## ۳) باگ حسابداری (Accounting)

### 3.1 `Staking.scheduleRewardProgram` — از دست رفتن پاداش‌های تسویه‌نشده
- **مشکل:** وقتی یه برنامه‌ی پاداش جدید زمان‌بندی می‌شد، تابع `_updateGlobal()` (که `rewardPerTokenStored` و `lastUpdateTime` رو با وضعیت فعلی سینک می‌کنه) صدا زده نمی‌شد. اگه بین پایان برنامه‌ی قبلی و زمان‌بندی برنامه‌ی جدید هیچ کاربری تعامل نکرده بود، پاداش‌های تولیدشده‌ی آخر دوره‌ی قبلی گم می‌شد (چون `lastUpdateTime` مستقیم روی `startAt` جدید ست می‌شد و اون بازه‌ی زمانی رد می‌شد).
- **اصلاح:** خط اول تابع، `_updateGlobal();` اضافه شد تا حساب‌ها قبل از ریست شدن، تسویه بشن.
- **فایل:** `core/Staking.sol`

---

## ۴) باگ سمانتیک (Semantic / پیام خطای گمراه‌کننده)

### 4.1 `ProtocolRegistry.setRegistrar` — ارور اشتباه برای آدرس صفر
- **مشکل:** چک `account == address(0)` با `UnauthorizedRegistrar()` رد می‌شد، در حالی که این ارور معنایی «دسترسی غیرمجاز» داره، نه «ورودی نامعتبر».
- **اصلاح:** ارور اختصاصی `ZeroAddress()` به `IRegistry` اضافه شد و به‌جاش استفاده شد.
- **فایل‌ها:** `interfaces/IRegistry.sol`, `registries/ProtocolRegistry.sol`

---

## ۵) حذف کد تکراری/مرده (Duplicate & Dead Code)

### 5.1 محاسبه‌ی fee در سه‌جا جدا پیاده شده بود
- `FeeMath.split` (استفاده در BlindAuction/OpenAuction)، `ListingMath.protocolFee/sellerProceeds` (در Marketplace)، و محاسبه‌ی دستی با `Math.mulDiv` در DutchAuction — هر سه دقیقاً یک فرمول (`amount * bps / 10000`) رو با کد جدا پیاده کرده بودن.
- **اصلاح:** `Marketplace` و `DutchAuction` هر دو به `FeeMath.split` منتقل شدن. `ListingMath` از منطق fee خالی شد و فقط `activeAt`/`isStale` (منطق انقضای لیستینگ) توش باقی موند.
- **فایل‌ها:** `core/Marketplace.sol`, `core/DutchAuction.sol`, `libraries/ListingMath.sol`

### 5.2 `PhaseLogic.expired()` عیناً کپی `PhaseLogic.afterEnd()` بود
- هر دو تابع دقیقاً `nowTs >= deadline` رو برمی‌گردوندن. `expired` هم هیچ‌جای پروژه استفاده نمی‌شد.
- **اصلاح:** `expired()` حذف شد، `afterEnd()` (که همون‌جا استفاده می‌شد) نگه داشته شد.
- **فایل:** `libraries/PhaseLogic.sol`

### 5.3 `RewardMath` — توابع بلااستفاده و رَپر اضافی
- `accumulated()` و `rewardPerShare()` هیچ‌جای کل پروژه صدا زده نمی‌شدن (مدل قدیمی‌تری بودن که با مدل accumulator فعلی `Staking` جایگزین شده بود).
- `userReward()` فقط یه رَپر بود که `userAccrued()` صداش می‌زد.
- **اصلاح:** `accumulated` و `rewardPerShare` حذف شدن؛ منطق `userReward` مستقیم داخل `userAccrued` ادغام شد (بدون تغییر در ورودی/خروجی، پس `Staking.sol` نیازی به تغییر نداشت).
- **فایل:** `libraries/RewardMath.sol`

---

## ۶) یکنواخت‌سازی جزئی (Consistency / گاز کمتر)

### 6.1 `revert("...")` رشته‌ای → ارور اختصاصی
- `OpenAuction`, `DutchAuction`, `PaymentManager` توی `receive()` با یه رشته‌ی متنی (`"DIRECT_ETH_DISABLED"`) رد می‌شدن، در حالی که `BlindAuction` از قبل الگوی درست (ارور اختصاصی، گازِ کمتر) رو داشت.
- **اصلاح:** ارور `DirectPaymentNotAllowed()` به `IAuction`, `IDutchAuction`, `IPaymentManager` اضافه شد و پیاده‌سازی‌ها به همون تغییر کردن.
- **فایل‌ها:** `interfaces/IAuction.sol`, `interfaces/IDutchAuction.sol`, `interfaces/IPaymentManager.sol`, `core/OpenAuction.sol`, `core/DutchAuction.sol`, `core/PaymentManager.sol`

### 6.2 `Marketplace.sol` — هدر SPDX جا افتاده بود
- تنها فایلی بود که `// SPDX-License-Identifier: MIT` رو نداشت (فقط warning می‌داد، نه error) — برای یکدستی با بقیه‌ی فایل‌ها اضافه شد.

---

## چیزهایی که **عمداً دست نخورد**

- `CustomNFT.MintPhase.Closed` و ارور `TokenURIUnset`: توی enum/اینترفیس تعریف شدن ولی پیاده‌سازی ازشون استفاده نمی‌کنه. این‌ها بی‌ضررن (فقط یه state/ارور رزرو نشده) و حذفشون ریسک بی‌خودی داره اگه جای دیگه‌ای از پروژه (که ندیدم) قراره ازشون استفاده کنه — دست نخوردن.
- `AccountingMath.safeSubtract`: بلااستفاده‌ست ولی تکراریِ چیز دیگه‌ای نیست (کد مستقل و بی‌ضرره) — حذف نشد.
- معماری «offer در Marketplace از طریق PaymentManager تسویه می‌شه ولی listing از طریق Treasury» — این یه تصمیم طراحی به‌نظر می‌رسه نه باگ، دست نخورد.
- منطق اصلی هر قرارداد (فرمول قیمت حراج هلندی، فرمول reward-per-token در Staking، قوانین escrow invariant، فرآیند mint/burn/transfer در CustomNFT، فرآیند bid/reveal در BlindAuction) — **هیچ‌کدوم تغییر نکردن**، فقط باگ‌ها و تکرارها رفع شدن.

---

## تأیید نهایی

از تک‌تک ۳۱ فایل پروژه عبور کردم و هر تابعی که در یک قرارداد پیاده‌سازی می‌شد رو با تعریفش در اینترفیس مربوطه (امضا، `override`، انواع پارامتر) تطبیق دادم، و جریان مالی/NFT بین قراردادها (Factory ↔ Treasury ↔ Marketplace/Auction/Staking ↔ CustomNFT) رو دنبال کردم تا مطمئن بشم فایل‌های به‌ظاهر سالم هم واقعاً با بقیه هماهنگ کار می‌کنن.
