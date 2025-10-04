# FaceTime Integration Testing Guide

## Testing Options

You have several ways to test the FaceTime integration for your trivia app.

## Option 1: Solo Testing (Quick Validation)

Test the basic flow with just your device:

### Steps:
1. **Create a test FaceTime Link**
   - Open FaceTime app
   - Tap "Create Link"
   - Copy the link

2. **Run the app as Host**
   - Create/join a test event
   - Open `TableFaceTimeLinkSetupView`
   - Paste the link for Table 1
   - Tap "Save"

3. **Verify Firebase**
   - Check Firebase Console
   - Look at `TableVoiceRooms` collection
   - Confirm `faceTimeURL` field exists

4. **Test the join flow**
   - Switch to participant view (if possible)
   - Tap "Join Table Call" button
   - Verify FaceTime app opens with the link
   - You'll join your own call (just yourself)

### What This Tests:
✅ Link storage in Firebase
✅ Link retrieval from Firebase
✅ FaceTime app launches correctly
✅ URL handling works
❌ Actual multi-user group calls

---

## Option 2: Two-Device Testing (Recommended)

Test real group calls with another device:

### Required:
- 2 devices (iPhone, iPad, Mac, Vision Pro)
- Both signed into FaceTime with Apple IDs
- Both can run your app (or use TestFlight)

### Steps:

**Device 1 (Host):**
1. Create FaceTime Link in FaceTime app
2. Run app as host
3. Set up event and paste FaceTime link for Table 1
4. Assign yourself to Table 1

**Device 2 (Participant):**
1. Install/run the app
2. Join the same event
3. Get assigned to Table 1
4. Tap "Join Table Call"

**Result:**
- Both devices should join the same FaceTime call
- You can talk to yourself between devices
- This tests the full group call flow

### What This Tests:
✅ Full group call functionality
✅ Multiple users joining same link
✅ Audio/video between participants
✅ Real-world user experience

---

## Option 3: Simulator Testing (Limited)

Test UI/logic without actual FaceTime:

### Steps:
1. Run app in visionOS Simulator
2. Create test event
3. Set up tables with fake FaceTime URLs:
   ```
   https://facetime.apple.com/join#v=1&p=TEST123
   ```
4. Verify UI shows/hides correctly
5. Check buttons enable/disable appropriately
6. Verify error messages for missing links

### Limitations:
❌ Can't actually join FaceTime calls
❌ Can't test opening FaceTime app
✅ Can test UI flows
✅ Can test Firebase read/write
✅ Can test error handling

---

## Option 4: Hybrid Testing (UI + Web Browser)

Test link validity without multiple devices:

### Steps:
1. Create real FaceTime Link on your device
2. Copy the link
3. Paste it into Safari on your Mac/iPad
4. The link should open FaceTime and show the call
5. Now paste the same link in your app
6. Join from the app on your Vision Pro
7. Both should connect to the same call

### What This Tests:
✅ Link format is correct
✅ Links work across platforms
✅ Same link joins same call
✅ URL parsing works

---

## Recommended Testing Flow

### Phase 1: Solo Validation (5 mins)
```
1. Create FaceTime Link
2. Save to Table 1 in app
3. Check Firebase Console
4. Tap "Join Table Call"
5. Verify FaceTime opens
```

### Phase 2: Two-Device Test (15 mins)
```
1. Set up host on Device 1
2. Create and save FaceTime Link
3. Join as participant on Device 2
4. Both join Table 1 call
5. Test audio/video communication
```

### Phase 3: Multi-Table Test (30 mins)
```
1. Create 3 FaceTime Links (Table 1, 2, 3)
2. Save all links in app
3. Assign users to different tables
4. Verify each table has separate calls
5. Test host joining different table calls
```

---

## Testing Checklist

### Host Features:
- [ ] Can open `TableFaceTimeLinkSetupView`
- [ ] Can paste FaceTime links for tables
- [ ] Links save to Firebase correctly
- [ ] Can see which tables have links (checkmark icon)
- [ ] Can join specific table calls via `HostAudioManager`

### Participant Features:
- [ ] Can see "Join Table Call" button
- [ ] Button disabled when no link available
- [ ] Shows "No FaceTime link available" message appropriately
- [ ] FaceTime opens when clicking button
- [ ] Joins correct table's call

### Firebase:
- [ ] `EventTable` documents have `faceTimeLinkURL` field
- [ ] `TableVoiceRooms` documents have `faceTimeURL` field
- [ ] Links persist across app restarts
- [ ] Multiple tables have separate links

### Error Handling:
- [ ] Shows error when link not found
- [ ] Shows error when link invalid
- [ ] Shows loading state while fetching
- [ ] Graceful failure when FaceTime unavailable

---

## Quick Test Script

### 1-Minute Smoke Test:
```swift
// Run this in your app's debug console or add as a test button

Task {
    // Create test link
    let testLink = "https://facetime.apple.com/join#v=1&p=TEST123ABC"

    // Save to table 1
    let result = await HostedEventManager.shared.updateTableFaceTimeLink(1, faceTimeURL: testLink)
    print("Save result: \(result)")

    // Retrieve from table 1
    if let retrieved = HostedEventManager.shared.getFaceTimeLinkForTable(1) {
        print("Retrieved: \(retrieved)")
        print("Match: \(retrieved == testLink)")
    }
}
```

---

## Common Issues & Solutions

### "No FaceTime link found"
**Cause:** Link not saved to Firebase yet
**Fix:** Run `TableFaceTimeLinkSetupView` and save links

### "Failed to open FaceTime"
**Cause:** Invalid URL format
**Fix:** Use real FaceTime links from FaceTime app, not test URLs

### Button stays disabled
**Cause:** `faceTimeURL` is nil in state
**Fix:** Check Firebase, ensure link was saved

### Can't join call
**Cause:** Not signed into FaceTime on device
**Fix:** Sign into FaceTime with Apple ID

---

## Testing Without Real Users

If you can't get multiple devices or users:

### Mock Testing:
1. Create FaceTime links for all tables
2. Save them in the app
3. Print/log when "Join" is tapped
4. Verify correct link is being used
5. Manually open links in browser to verify they work

### Automated Testing:
```swift
// Add to your test suite
func testFaceTimeLinkFlow() async {
    let manager = HostedEventManager.shared

    // Test save
    let result = await manager.updateTableFaceTimeLink(1, faceTimeURL: "https://facetime.apple.com/test")
    XCTAssertEqual(result, .success(()))

    // Test retrieve
    let link = manager.getFaceTimeLinkForTable(1)
    XCTAssertEqual(link, "https://facetime.apple.com/test")
}
```

---

## Production Testing Tips

1. **Start with 1 table** - Get it working perfectly first
2. **Use real FaceTime links** - Don't use test/fake URLs
3. **Test table switching** - Ensure users can change tables
4. **Test reconnection** - What happens if call drops?
5. **Test host controls** - Can host join/leave different tables?

---

## Need Help?

If you encounter issues:
1. Check console logs for error messages
2. Verify Firebase has the links stored
3. Try opening the link directly in Safari
4. Ensure FaceTime is signed in on all devices
5. Check `FACETIME_SETUP_GUIDE.md` for architecture details
