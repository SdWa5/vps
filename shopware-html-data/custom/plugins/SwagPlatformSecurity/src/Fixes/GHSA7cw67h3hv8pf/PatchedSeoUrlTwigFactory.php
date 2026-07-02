<?php declare(strict_types=1);

namespace Swag\Security\Fixes\GHSA7cw67h3hv8pf;

use Cocur\Slugify\Bridge\Twig\SlugifyExtension;
use Cocur\Slugify\SlugifyInterface;
use Shopware\Core\Content\Seo\SeoUrlGenerator;
use Shopware\Core\Content\Seo\SeoUrlTwigFactory;
use Shopware\Core\Framework\Adapter\Twig\Extension\PhpSyntaxExtension;
use Shopware\Core\Framework\Adapter\Twig\TwigEnvironment;
use Symfony\Component\Filesystem\Path;
use Twig\Cache\FilesystemCache;
use Twig\Environment;
use Twig\Extension\ExtensionInterface;
use Twig\Loader\ArrayLoader;
use Twig\Runtime\EscaperRuntime;

class PatchedSeoUrlTwigFactory extends SeoUrlTwigFactory
{
    /**
     * @param ExtensionInterface[] $twigExtensions
     */
    public function createTwigEnvironment(SlugifyInterface $slugify, iterable $twigExtensions, string $cacheDir): Environment
    {
        $twig = new TwigEnvironment(new ArrayLoader());

        if ($cacheDir) {
            $twig->setCache(new FilesystemCache(Path::join($cacheDir, 'twig', 'seo-cache')));
        } else {
            $twig->setCache(false);
        }

        $twig->enableStrictVariables();
        $twig->addExtension(new SlugifyExtension($slugify));
        /** @phpstan-ignore-next-line new.deprecatedClass (This fix mirrors the vulnerable Shopware versions where the class is not internal yet.) */
        $twig->addExtension(new PhpSyntaxExtension());
        $twig->addExtension(new PatchedSecurityExtension([]));

        foreach ($twigExtensions as $twigExtension) {
            $twig->addExtension($twigExtension);
        }

        $twig->getRuntime(EscaperRuntime::class)->setEscaper(
            SeoUrlGenerator::ESCAPE_SLUGIFY,
            static fn (string $string) => rawurlencode($slugify->slugify($string))
        );

        return $twig;
    }
}
