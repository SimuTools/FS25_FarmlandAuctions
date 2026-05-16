# Farmland Auctions

**Farmland Auctions** adds regular farmland auctions to Farming Simulator 25.

Instead of simply buying land directly, fields can be purchased through an auction system. Players can place bids directly on the auctioned farmland, creating a more dynamic and competitive way to buy land.

## Features

- Regular automatic farmland auctions
- Place bids directly on the field using the **B key**
- Each new bid increases the current auction price
- Alternative land purchase system
- Optional NPC bidding
- Optional “Auction Only” mode
- Blocks the default land purchase option when auction-only mode is enabled
- Multiplayer support
- Farms can bid against each other in multiplayer
- Console commands for auction management

## How It Works

When an auction is active, players can bid directly on the affected farmland.

To place a bid, the player must be standing on the auctioned farmland and press the **B key**.  
This increases the current bid.

In multiplayer, different farms can bid against each other. Once the auction ends, the farm with the highest bid wins the farmland.

## Mod Settings

The mod settings allow you to adjust several options:

- Enable or disable NPC bids
- Decide whether farmland can only be purchased through auctions
- Disable the default land purchase option when auction-only mode is active

## Console Commands

The following console commands are available:

```txt
faStartNow
```

Starts the next auction immediately.

```txt
faStartAuction <farmlandId>
```

Manually starts an auction for a specific farmland.

```txt
faEndNow
```

Immediately ends the currently active auction.

```txt
faCancelAuction
```

Cancels the current or scheduled auction.

```txt
faSetAuctionTime <min> <max>
```

Sets the minimum and maximum auction duration.

```txt
faSetStartInterval <min> <max>
```

Sets the minimum and maximum time before the next auction starts.

## Multiplayer

This mod is designed to work in multiplayer.

In multiplayer, multiple farms can bid on the same farmland. This creates direct competition between farms and makes land purchases more interesting than the default instant-buy system.

## Auction Only

When auction-only mode is enabled, farmland can no longer be bought normally.

The default purchase option is blocked, and land can only be acquired through auctions.

## Changelog

### Version 1.0.0.1

- Fixed multiplayer issues
- Fixed timing issue

### Version 1.0.0.0

- Initial release
- Added regular farmland auctions
- Added direct field bidding using the B key
- Added NPC bidding
- Added auction-only mode
- Added console commands for auction management
- Added multiplayer support

## Notes

This mod changes the farmland purchase system and is especially useful for servers that want a more realistic and long-term economy.

For a fair multiplayer experience, the auction settings should be configured before starting a server.
