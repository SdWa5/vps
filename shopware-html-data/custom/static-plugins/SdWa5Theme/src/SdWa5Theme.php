<?php

declare(strict_types=1);

namespace SdWa5Theme;

use Shopware\Core\Framework\Plugin;
use Shopware\Storefront\Framework\ThemeInterface;

/**
 * Storefront theme of sdwa5.org.
 *
 * The design is ported from the ChimodiazzTheme, which is dark only. This shop
 * keeps the DNE dark mode plugin instead, so the theme ships light values and
 * lets the plugin derive the dark ones. See docs/shopware/theme.md.
 */
class SdWa5Theme extends Plugin implements ThemeInterface
{
    /**
     * Since Shopware 6.7 ThemeInterface is a marker interface and theme.json is
     * found by convention under src/Resources/. The method stays as an explicit
     * pointer and does no harm.
     */
    public function getThemeConfigPath(): string
    {
        return 'theme.json';
    }
}
