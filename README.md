<p align="center"><img src="assets/icon-1024.png" width="128" alt="XPad icon"></p>

<h1 align="center">XPad for Mac</h1>

<p align="center"><b>Use an Xbox 360‑style (XInput) controller in Chrome on your Mac — as a real, analog gamepad.</b><br>
Free Chrome extension · no driver · no kernel extension · no SIP changes · Apple Silicon & Intel</p>

<p align="center"><a href="https://github.com/OGskrrt/XPad-for-Mac/archive/refs/heads/main.zip"><b>⬇ Download XPad (ZIP)</b></a> · <a href="https://ogskrrt.github.io/XPad-for-Mac/">Website</a> · <a href="https://ogskrrt.github.io/XPad-for-Mac/tr/">Türkçe</a></p>

**XPad** is a free, open-source Chrome extension that makes Xbox 360-style USB controllers work in browser games on a Mac. These controllers and their 2.4 GHz USB receivers (for example the **8BitDo Ultimate C 2.4G**) use Microsoft's XInput protocol, which macOS has no driver for, so Chrome doesn't see them. XPad reads the controller directly with Chrome's WebUSB and shows it to every tab as a standard Xbox 360 gamepad, with analog sticks and triggers.

## Why doesn't my controller work on Mac?

macOS supports standard HID gamepads plus Xbox One/Series, PlayStation and MFi controllers. Xbox 360 controllers and many third-party pads in "X-input" mode use a vendor-specific USB protocol. The Mac lists the device in System Information, but browsers and games can't use it. The old fix, the 360Controller kernel extension, is no longer maintained and needs lowered security on Apple Silicon. XPad needs none of that.

## Install (2 minutes)

1. [Download the ZIP](https://github.com/OGskrrt/XPad-for-Mac/archive/refs/heads/main.zip) and double-click it to unzip.
2. In Chrome, go to `chrome://extensions` and turn on **Developer mode** (top right).
3. Click **Load unpacked** and choose the **`extension`** folder inside the unzipped folder.
4. The XPad tab opens. Plug in your controller (or its USB receiver), switch it on, click **Connect controller** and pick it from the list.
5. Open any browser game. Keep the XPad tab open while you play.

Test it at [hardwaretester.com/gamepad](https://hardwaretester.com/gamepad): it should show **Xbox 360 Controller**.

## FAQ

**Which controllers work?**
USB controllers and receivers that use the Xbox 360 (XInput) protocol: wired Xbox 360 controllers and third-party pads in X-input mode. Tested with the 8BitDo Ultimate C 2.4G. Xbox One/Series, PlayStation and Switch Pro controllers already work in Chrome on macOS without XPad.

**Which games?**
Any web game or cloud gaming site that uses the standard Gamepad API. Tested with nfsu2.xyz and hardwaretester.com.

**Does it work in Safari or Firefox?**
No. It needs Chrome's WebUSB. Other Chromium browsers (Edge, Brave, Arc) should work the same way.

**Does it work on Apple Silicon?**
Yes, on M1–M4 and Intel Macs. Nothing is installed into macOS.

**Why must the XPad tab stay open?**
Some sites block USB access in their own pages, so XPad reads the controller in its own tab and passes the input to your game tabs.

**"Controller is in use by another app or tab".**
Only one program can use a USB controller at a time. Close the other app or the second XPad tab.

**Privacy?**
XPad has no network access and collects nothing. It only reads your controller and passes its buttons and sticks to pages that ask for a gamepad.

**Is it free?**
Yes. Free and open source under the MIT license.

## License

MIT. Not affiliated with Microsoft, Xbox or 8BitDo; product names are used only to describe compatibility.
